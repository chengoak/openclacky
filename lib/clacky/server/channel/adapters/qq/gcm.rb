# frozen_string_literal: true

require "openssl"
require "base64"

module Clacky
  module Channel
    module Adapters
      module Qq
        # AES-256-GCM decryption with a robust fallback.
        #
        # The OpenSSL::Cipher path is preferred. On macOS system Ruby 2.6 the
        # bundled openssl gem (2.1.2) against LibreSSL 3.3.x raises a generic
        # CipherError for GCM operations, so we fall back to driving libcrypto
        # directly through Fiddle. That path is only taken when the native
        # cipher fails and only on a supported platform.
        module Gcm
          # Nonce length and tag length used by the QQ lite-bind protocol.
          NONCE_LEN = 12
          TAG_LEN   = 16

          # Direct libcrypto EVP bindings used only as a GCM fallback.
          module LibCrypto
            EVP_CTRL_GCM_SET_IVLEN = 0x9
            EVP_CTRL_GCM_SET_TAG   = 0x11

            @handle = nil

            def self.handle
              @handle ||= Fiddle.dlopen(lib_path)
            end

            def self.lib_path
              candidates = ["/usr/lib/libcrypto.dylib", "libcrypto.3.dylib", "libcrypto.so.3", "libcrypto.so.1.1"]
              found = candidates.find do |p|
                Fiddle.dlopen(p)
                true
              rescue Fiddle::DLError
                false
              end
              raise LoadError, "libcrypto not found for GCM fallback" unless found

              found
            end

            def self.func(name, signature)
              Fiddle::Function.new(handle[name], signature, Fiddle::TYPE_INT)
            end

            # Decrypt and verify using raw libcrypto EVP calls.
            def self.decrypt(key, nonce, ciphertext, tag)
              require "fiddle"

              pvoid  = Fiddle::TYPE_VOIDP
              pint   = Fiddle::TYPE_INT

              ctx_new    = Fiddle::Function.new(handle["EVP_CIPHER_CTX_new"], [], pvoid)
              ctx_free_f = Fiddle::Function.new(handle["EVP_CIPHER_CTX_free"], [pvoid], Fiddle::TYPE_VOID)
              aes_gcm_f  = Fiddle::Function.new(handle["EVP_aes_256_gcm"], [], pvoid)
              init_ex    = func("EVP_DecryptInit_ex", [pvoid, pvoid, pvoid, pvoid, pvoid])
              ctrl       = func("EVP_CIPHER_CTX_ctrl", [pvoid, pint, pint, pvoid])
              update_f   = func("EVP_DecryptUpdate", [pvoid, pvoid, pvoid, pvoid, pint])
              final_f    = func("EVP_DecryptFinal_ex", [pvoid, pvoid, pvoid])

              ctx = ctx_new.call
              raise "EVP_CIPHER_CTX_new failed" if ctx.null?

              begin
                cipher = aes_gcm_f.call
                check(init_ex.call(ctx, cipher, nil, nil, nil), "init")
                check(init_ex.call(ctx, nil, nil, Fiddle::Pointer.to_ptr(key), nil), "set key")
                check(ctrl.call(ctx, EVP_CTRL_GCM_SET_IVLEN, nonce.bytesize, nil), "set iv length")
                check(init_ex.call(ctx, nil, nil, nil, Fiddle::Pointer.to_ptr(nonce)), "set iv")

                out = "\0" * (ciphertext.bytesize + 16)
                out_len = [0].pack("i")
                check(update_f.call(ctx, Fiddle::Pointer.to_ptr(out), Fiddle::Pointer.to_ptr(out_len),
                                    Fiddle::Pointer.to_ptr(ciphertext), ciphertext.bytesize), "update")
                produced = out_len.unpack1("i")

                check(ctrl.call(ctx, EVP_CTRL_GCM_SET_TAG, tag.bytesize, Fiddle::Pointer.to_ptr(tag)), "set tag")

                final_buf = "\0" * 32
                final_len = [0].pack("i")
                check(final_f.call(ctx, Fiddle::Pointer.to_ptr(final_buf), Fiddle::Pointer.to_ptr(final_len)),
                      "auth tag")

                out.byteslice(0, produced)
              ensure
                ctx_free_f.call(ctx)
              end
            end

            def self.check(code, step)
              raise OpenSSL::Cipher::CipherError, "GCM #{step} failed" unless code == 1
            end
          end

          # Decrypt an AES-256-GCM payload.
          #
          # @param aes_key    [String] 32-byte key
          # @param nonce      [String] 12-byte nonce
          # @param ciphertext [String] encrypted bytes
          # @param tag        [String] 16-byte auth tag
          # @return [String] plaintext
          def self.decrypt(aes_key, nonce, ciphertext, tag)
            cipher_decrypt(aes_key, nonce, ciphertext, tag)
          rescue OpenSSL::Cipher::CipherError
            LibCrypto.decrypt(aes_key, nonce, ciphertext, tag)
          end

          def self.cipher_decrypt(aes_key, nonce, ciphertext, tag)
            cipher = OpenSSL::Cipher.new("aes-256-gcm")
            cipher.decrypt
            cipher.key = aes_key
            cipher.iv  = nonce
            cipher.auth_tag = tag
            cipher.update(ciphertext) + cipher.final
          end
        end
      end
    end
  end
end
