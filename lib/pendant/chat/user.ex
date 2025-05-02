defmodule Pendant.Chat.User do
  @moduledoc """
  Schema for chat users.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Pendant.Chat.Message

  schema "chat_users" do
    field :username, :string
    field :display_name, :string
    field :device_id, :string
    field :avatar, :string
    field :status, :string, default: "online"
    field :metadata, :map, default: %{}
    field :last_seen_at, :utc_datetime
    
    has_many :messages, Message

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :display_name, :device_id, :avatar, :status, :metadata, :last_seen_at])
    |> validate_required([:username, :device_id])
    |> unique_constraint(:username)
    |> unique_constraint(:device_id)
  end
end