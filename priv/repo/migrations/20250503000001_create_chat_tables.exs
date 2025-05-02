defmodule Pendant.KnowledgeBase.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  def change do
    # Users table
    create table(:chat_users) do
      add :username, :string, null: false
      add :display_name, :string
      add :device_id, :string, null: false
      add :avatar, :string
      add :status, :string
      add :metadata, :map
      add :last_seen_at, :utc_datetime

      timestamps()
    end
    create unique_index(:chat_users, [:username])
    create unique_index(:chat_users, [:device_id])
    
    # Rooms table
    create table(:chat_rooms) do
      add :name, :string, null: false
      add :description, :text
      add :room_type, :string, null: false
      add :metadata, :map
      add :crdt_enabled, :boolean, default: false
      add :crdt_type, :string
      add :crdt_data, :map, default: %{}

      timestamps()
    end
    create unique_index(:chat_rooms, [:name])
    
    # User-Room relationship table
    create table(:chat_user_rooms) do
      add :user_id, references(:chat_users), null: false
      add :room_id, references(:chat_rooms), null: false
      add :role, :string, null: false
      add :metadata, :map
      add :last_read_at, :utc_datetime

      timestamps()
    end
    create unique_index(:chat_user_rooms, [:user_id, :room_id])
    
    # Messages table
    create table(:chat_messages) do
      add :content, :text, null: false
      add :message_type, :string, null: false
      add :metadata, :map
      add :file_path, :string
      add :file_name, :string
      add :file_size, :integer
      add :file_type, :string
      add :user_id, references(:chat_users), null: false
      add :room_id, references(:chat_rooms), null: false

      timestamps()
    end
    create index(:chat_messages, [:user_id])
    create index(:chat_messages, [:room_id])
    create index(:chat_messages, [:inserted_at])
  end
end