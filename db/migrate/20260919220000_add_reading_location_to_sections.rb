# Stage 30: a leaf carries two locations over the same span. location_id is the
# anchor, quoted exactly and checked against the source by retrieval.
# reading_location_id is the section text as an assistant read it, cleaned into
# paragraphs, which is readable but is not a quotation and is never checked
# against the source.
class AddReadingLocationToSections < ActiveRecord::Migration[8.1]
  def change
    add_column :sections, :reading_location_id, :uuid
    add_index :sections, :reading_location_id
  end
end
