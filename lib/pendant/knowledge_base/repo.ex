defmodule Pendant.KnowledgeBase.Repo do
  @moduledoc """
  SQLite repository for the knowledge base.
  """
  use Ecto.Repo,
    otp_app: :pendant,
    adapter: Ecto.Adapters.SQLite3
    
  @doc """
  Initialize the database schema after connection is established.
  """
  def init(_type, config) do
    # Return the configuration
    {:ok, config}
  end
  
  def after_connect(_conn) do
    # Create necessary tables and indexes if they don't exist
    migrate()
  end
  
  defp migrate do
    # Run migrations to ensure the schema is up to date
    migrations_dir = Application.app_dir(:pendant, "priv/repo/migrations")
    
    # Check if migrations directory exists, create if not
    unless File.exists?(migrations_dir) do
      File.mkdir_p!(migrations_dir)
      
      # Create the initial migration
      create_initial_migration(migrations_dir)
    end
    
    # Run the migrations
    Ecto.Migrator.run(__MODULE__, migrations_dir, :up, all: true)
  end
  
  defp create_initial_migration(migrations_dir) do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d%H%M%S")
    filename = "#{migrations_dir}/#{timestamp}_create_knowledge_base_tables.exs"
    
    migration_content = """
    defmodule Pendant.KnowledgeBase.Repo.Migrations.CreateKnowledgeBaseTables do
      use Ecto.Migration
    
      def change do
        create table(:categories) do
          add :name, :string, null: false
          add :description, :text
          add :icon, :string
    
          timestamps()
        end
        create unique_index(:categories, [:name])
    
        create table(:articles) do
          add :title, :string, null: false
          add :content, :text, null: false
          add :summary, :text
          add :category_id, references(:categories)
          add :importance, :integer, default: 1
          add :tags, :string
    
          timestamps()
        end
        create index(:articles, [:category_id])
        create index(:articles, [:importance])
      end
    end
    """
    
    File.write!(filename, migration_content)
  end
end