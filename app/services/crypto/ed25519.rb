# frozen_string_literal: true

module Crypto
  # Ed25519 signatures via Ruby's OpenSSL 3 bindings; no hand-rolled primitives
  # (spec 05 §2). Keys and signatures travel as unpadded base64url. The key id is
  # "ed25519:" + hex(sha256(raw public key)).
  module Ed25519
    KEY_ID_PREFIX = "ed25519:"
    KEY_ID_FORMAT = /\Aed25519:\h{64}\z/
    ALGORITHM = "ED25519"

    class KeyPair
      def self.generate
        new(OpenSSL::PKey.generate_key(ALGORITHM))
      end

      def self.from_private_key(private_key_b64)
        new(OpenSSL::PKey.new_raw_private_key(ALGORITHM, Ed25519.decode(private_key_b64)))
      end

      def initialize(pkey)
        @pkey = pkey
      end

      def public_key
        Ed25519.encode(@pkey.raw_public_key)
      end

      def private_key
        Ed25519.encode(@pkey.raw_private_key)
      end

      def key_id
        Ed25519.key_id(public_key)
      end

      # Signs raw bytes (callers pass canonical JSON). Returns base64url.
      def sign(bytes)
        Ed25519.encode(@pkey.sign(nil, bytes))
      end
    end

    def self.key_id(public_key_b64)
      "#{KEY_ID_PREFIX}#{Digest::SHA256.hexdigest(decode(public_key_b64))}"
    end

    # True only when the signature was produced by the holder of the given
    # public key over exactly these bytes. Malformed input is simply invalid.
    def self.verify(public_key_b64, signature_b64, bytes)
      pkey = OpenSSL::PKey.new_raw_public_key(ALGORITHM, decode(public_key_b64))
      pkey.verify(nil, decode(signature_b64), bytes)
    rescue OpenSSL::PKey::PKeyError, ArgumentError
      false
    end

    def self.encode(raw)
      Base64.urlsafe_encode64(raw, padding: false)
    end

    def self.decode(b64)
      Base64.urlsafe_decode64(b64.to_s)
    end
  end
end
