# An affiliation an admin added because people asked for it. Folded into the
# vocabulary by Affiliations.groups under its group, or under "Other".
class CustomAffiliation < ApplicationRecord
  SLUG = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

  validates :slug, presence: true, uniqueness: true, format: { with: SLUG }
  validates :label, presence: true, length: { maximum: 80 }
  validates :group_slug, inclusion: { in: ->(_) { Affiliations.group_slugs } }
  validate :slug_not_curated

  def self.slug_for(label) = label.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")

  private

  def slug_not_curated
    errors.add(:slug, "is already a curated affiliation") if Affiliations.curated_groups.flat_map(&:options).any? { |o| o.slug == slug }
  end
end
