defmodule Pendant.Chat.UserRoom do
  @moduledoc """
  Schema for user-room relationships.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Pendant.Chat.{User, Room}

  schema "chat_user_rooms" do
    field :role, :string, default: "member"  # member, admin, owner
    field :metadata, :map, default: %{}
    field :last_read_at, :utc_datetime
    
    belongs_to :user, User
    belongs_to :room, Room

    timestamps()
  end

  @doc false
  def changeset(user_room, attrs) do
    user_room
    |> cast(attrs, [:role, :metadata, :last_read_at, :user_id, :room_id])
    |> validate_required([:role, :user_id, :room_id])
    |> validate_inclusion(:role, ["member", "admin", "owner"])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:room_id)
    |> unique_constraint([:user_id, :room_id])
  end
end