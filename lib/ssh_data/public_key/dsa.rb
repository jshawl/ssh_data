module SSHData
  module PublicKey
    class DSA < Base
      attr_reader :p, :q, :g, :y

      # Convert an SSH encoded DSA signature to DER encoding for verification with
      # OpenSSL.
      #
      # sig - A binary String signature from an SSH packet.
      #
      # Returns a binary String signature, as expected by OpenSSL.
      def self.openssl_signature(sig)
        if sig.bytesize != 40
          raise DecodeError, "bad DSA signature size"
        end

        r = OpenSSL::BN.new(sig.byteslice(0, 20), 2)
        s = OpenSSL::BN.new(sig.byteslice(20, 20), 2)

        OpenSSL::ASN1::Sequence.new([
          OpenSSL::ASN1::Integer.new(r),
          OpenSSL::ASN1::Integer.new(s)
        ]).to_der
      end

      # Convert an DER encoded DSA signature, as generated by OpenSSL to SSH
      # encoding.
      #
      # sig - A binary String signature, as generated by OpenSSL.
      #
      # Returns a binary String signature, as found in an SSH packet.
      def self.ssh_signature(sig)
        a1 = OpenSSL::ASN1.decode(sig)
        if a1.tag_class != :UNIVERSAL || a1.tag != OpenSSL::ASN1::SEQUENCE || a1.value.count != 2
          raise DecodeError, "bad asn1 signature"
        end

        r, s = a1.value
        if r.tag_class != :UNIVERSAL || r.tag != OpenSSL::ASN1::INTEGER || s.tag_class != :UNIVERSAL || s.tag != OpenSSL::ASN1::INTEGER
          raise DecodeError, "bad asn1 signature"
        end

        # left pad big endian representations to 20 bytes and concatenate
        [
          "\x00" * (20 - r.value.num_bytes),
          r.value.to_s(2),
          "\x00" * (20 - s.value.num_bytes),
          s.value.to_s(2)
        ].join
      end

      def initialize(algo:, p:, q:, g:, y:)
        unless algo == ALGO_DSA
          raise DecodeError, "bad algorithm: #{algo.inpsect}"
        end

        @algo = algo
        @p = p
        @q = q
        @g = g
        @y = y
      end

      # The public key represented as an OpenSSL object.
      #
      # Returns an OpenSSL::PKey::PKey instance.
      def openssl
        @openssl ||= OpenSSL::PKey::DSA.new(asn1.to_der)
      end

      # Verify an SSH signature.
      #
      # signed_data - The String message that the signature was calculated over.
      # signature   - The binarty String signature with SSH encoding.
      #
      # Returns boolean.
      def verify(signed_data, signature)
        sig_algo, ssh_sig, _ = Encoding.decode_signature(signature)
        if sig_algo != ALGO_DSA
          raise DecodeError, "bad signature algorithm: #{sig_algo.inspect}"
        end

        openssl_sig = self.class.openssl_signature(ssh_sig)
        openssl.verify(OpenSSL::Digest::SHA1.new, openssl_sig, signed_data)
      end

      private

      def asn1
        OpenSSL::ASN1::Sequence.new([
          OpenSSL::ASN1::Sequence.new([
            OpenSSL::ASN1::ObjectId.new("DSA"),
            OpenSSL::ASN1::Sequence.new([
              OpenSSL::ASN1::Integer.new(p),
              OpenSSL::ASN1::Integer.new(q),
              OpenSSL::ASN1::Integer.new(g),
            ]),
          ]),
          OpenSSL::ASN1::BitString.new(OpenSSL::ASN1::Integer.new(y).to_der),
        ])
      end
    end
  end
end
