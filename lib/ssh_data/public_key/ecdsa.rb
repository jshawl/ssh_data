module SSHData
  module PublicKey
    class ECDSA < Base
      attr_reader :curve, :public_key

      OPENSSL_CURVE_NAME_FOR_CURVE = {
        "nistp256" => "prime256v1",
        "nistp384" => "secp384r1",
        "nistp521" => "secp521r1",
      }

      DIGEST_FOR_CURVE = {
        "nistp256" => OpenSSL::Digest::SHA256,
        "nistp384" => OpenSSL::Digest::SHA384,
        "nistp521" => OpenSSL::Digest::SHA512,
      }

      # Convert an SSH encoded ECDSA signature to DER encoding for verification with
      # OpenSSL.
      #
      # sig - A binary String signature from an SSH packet.
      #
      # Returns a binary String signature, as expected by OpenSSL.
      def self.openssl_signature(sig)
        r, rlen = Encoding.decode_mpint(sig, 0)
        s, slen = Encoding.decode_mpint(sig, rlen)

        if rlen + slen != sig.bytesize
          raise DecodeError, "unexpected trailing data"
        end

        OpenSSL::ASN1::Sequence.new([
          OpenSSL::ASN1::Integer.new(r),
          OpenSSL::ASN1::Integer.new(s)
        ]).to_der
      end

      # Convert an DER encoded ECDSA signature, as generated by OpenSSL to SSH
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

        [Encoding.encode_mpint(r.value), Encoding.encode_mpint(s.value)].join
      end

      def initialize(algo:, curve:, public_key:)
        unless [ALGO_ECDSA256, ALGO_ECDSA384, ALGO_ECDSA521].include?(algo)
          raise DecodeError, "bad algorithm: #{algo.inpsect}"
        end

        @algo = algo
        @curve = curve
        @public_key = public_key
      end

      # The public key represented as an OpenSSL object.
      #
      # Returns an OpenSSL::PKey::PKey instance.
      def openssl
        @openssl ||= OpenSSL::PKey::EC.new(asn1.to_der)
      end

      # Verify an SSH signature.
      #
      # signed_data - The String message that the signature was calculated over.
      # signature   - The binarty String signature with SSH encoding.
      #
      # Returns boolean.
      def verify(signed_data, signature)
        sig_algo, ssh_sig, _ = Encoding.decode_signature(signature)
        if sig_algo != "ecdsa-sha2-#{curve}"
          raise DecodeError, "bad signature algorithm: #{sig_algo.inspect}"
        end

        openssl_sig = self.class.openssl_signature(ssh_sig)
        digest = DIGEST_FOR_CURVE[curve]

        openssl.verify(digest.new, openssl_sig, signed_data)
      end

      private

      def asn1
        unless name = OPENSSL_CURVE_NAME_FOR_CURVE[curve]
          raise DecodeError, "unknown curve: #{curve.inspect}"
        end

        OpenSSL::ASN1::Sequence.new([
          OpenSSL::ASN1::Sequence.new([
            OpenSSL::ASN1::ObjectId.new("id-ecPublicKey"),
            OpenSSL::ASN1::ObjectId.new(name),
          ]),
          OpenSSL::ASN1::BitString.new(public_key),
        ])
      end
    end
  end
end
