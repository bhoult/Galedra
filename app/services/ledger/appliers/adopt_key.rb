# frozen_string_literal: true

module Ledger
  module Appliers
    # ADOPT_KEY (IMPLEMENTATION.md, "Adoption"): a signed-in person puts an
    # anonymous key's work under their own key. Signed by the adopter's human
    # key; the payload carries a signature by the adopted key over
    # {"adopt": adopter_key_id, "key_id": adopted_key_id}, proving control of
    # both. The adopted key keeps its own rows and reputation buckets; it
    # stops being anonymous and points at its adopter, visibly, at this seq.
    module AdoptKey
      extend Checks

      def self.authorize!(validated)
        payload = validated.payload
        signer = validated.contributor
        reject("NOT_AUTHORIZED", "$.signer_key_id", "only a HUMAN key may adopt") unless signer&.human?
        reject("NOT_AUTHORIZED", "$.signer_key_id", "an anonymous key cannot adopt") if signer.anonymous?

        target = Contributor.find_by(key_id: payload["key_id"].to_s)
        reject("KEY_UNKNOWN", "$.payload.key_id", "no registered contributor has this key") if target.nil?
        reject("ALREADY_ADOPTED", "$.payload.key_id", "adopted at seq #{target.metadata['adopted_seq']}") if target.metadata["adopted_by"].present?
        reject("NOT_ADOPTABLE", "$.payload.key_id", "only an ANONYMOUS key can be adopted") unless target.anonymous?
        reject("KEY_REVOKED", "$.payload.key_id", "revoked at seq #{target.revoked_seq}") if target.revoked?

        signature = payload["adoption_signature"]
        reject("SCHEMA_INVALID", "$.payload.adoption_signature", "expected a base64url signature by the adopted key") unless signature.is_a?(String) && signature.present?
        unless Crypto::Ed25519.verify(target.public_key, signature, challenge(signer.key_id, target.key_id))
          reject("SIGNATURE_INVALID", "$.payload.adoption_signature", "does not verify against the adopted key")
        end
      end

      def self.challenge(adopter_key_id, adopted_key_id)
        Crypto::CanonicalJson.call({ "adopt" => adopter_key_id, "key_id" => adopted_key_id })
      end

      def self.apply(contribution)
        target = Contributor.find_by!(key_id: contribution.payload["key_id"])
        adopter = contribution.contributor
        target.update!(identity_tier: adopter.identity_tier,
                       metadata: target.metadata.merge("adopted_by" => adopter.key_id, "adopted_seq" => contribution.seq))
      end
    end
  end
end
