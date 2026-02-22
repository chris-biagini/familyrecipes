class CreateSiteDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :site_documents do |t|
      t.string :name, null: false
      t.text :content, null: false

      t.timestamps
    end

    add_index :site_documents, :name, unique: true
  end
end
