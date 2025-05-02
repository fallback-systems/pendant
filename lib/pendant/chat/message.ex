defmodule Pendant.Chat.Message do
  @moduledoc """
  Schema for chat messages.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Pendant.Chat.{User, Room}

  schema "chat_messages" do
    field :content, :string
    field :message_type, :string, default: "text"  # text, file, system
    field :metadata, :map, default: %{}
    
    # For file attachments
    field :file_path, :string
    field :file_name, :string
    field :file_size, :integer
    field :file_type, :string
    
    belongs_to :user, User
    belongs_to :room, Room

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :message_type, :metadata, :user_id, :room_id, 
                    :file_path, :file_name, :file_size, :file_type])
    |> validate_required([:content, :message_type, :user_id, :room_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:room_id)
  end
end