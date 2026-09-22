# A reader's preferred scoring model, kept so they need not append ?model= to
# every link. A preference, not a claim about the world: it changes which
# model's answer a page shows and nothing about what is recorded.
class AddPreferredModelToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :preferred_model, :string
  end
end
