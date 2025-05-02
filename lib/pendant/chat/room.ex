defmodule Pendant.Chat.Room do
  @moduledoc """
  Schema for chat rooms.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Pendant.Chat.{Message, UserRoom, User}

  schema "chat_rooms" do
    field :name, :string
    field :description, :string
    field :room_type, :string, default: "public"  # public, private, direct
    field :metadata, :map, default: %{}
    
    # For CRDT data
    field :crdt_enabled, :boolean, default: false
    field :crdt_type, :string  # "lww" (last-write-wins), "counter", "set", etc.
    field :crdt_data, :map, default: %{}
    
    has_many :messages, Message
    has_many :user_rooms, UserRoom
    has_many :users, through: [:user_rooms, :user]

    timestamps()
  end

  @doc false
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :description, :room_type, :metadata, 
                   :crdt_enabled, :crdt_type, :crdt_data])
    |> validate_required([:name, :room_type])
    |> validate_inclusion(:room_type, ["public", "private", "direct"])
    |> validate_crdt_type()
    |> unique_constraint(:name)
  end
  
  defp validate_crdt_type(changeset) do
    if get_field(changeset, :crdt_enabled) do
      changeset
      |> validate_required([:crdt_type])
      |> validate_inclusion(:crdt_type, ["lww", "counter", "set", "text", "document", "map"])
    else
      changeset
    end
  end
end