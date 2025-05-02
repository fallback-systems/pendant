defmodule Pendant.Test.Schema do
  @moduledoc """
  Schema creation for test database.
  """
  
  alias Pendant.KnowledgeBase.Repo
  
  @doc """
  Creates schema for testing.
  """
  def create do
    # Create User table
    Repo.query!("""
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY,
      username TEXT NOT NULL UNIQUE,
      display_name TEXT NOT NULL,
      device_id TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL DEFAULT 'offline',
      last_seen_at TIMESTAMP,
      avatar TEXT,
      inserted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
    """)
    
    # Create Room table
    Repo.query!("""
    CREATE TABLE IF NOT EXISTS rooms (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      room_type TEXT NOT NULL DEFAULT 'public',
      description TEXT,
      crdt_enabled BOOLEAN NOT NULL DEFAULT FALSE,
      crdt_type TEXT,
      crdt_data TEXT,
      inserted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
    """)
    
    # Create UserRoom table
    Repo.query!("""
    CREATE TABLE IF NOT EXISTS user_rooms (
      id INTEGER PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id),
      room_id INTEGER NOT NULL REFERENCES rooms(id),
      role TEXT NOT NULL DEFAULT 'member',
      last_read_at TIMESTAMP,
      inserted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, room_id)
    )
    """)
    
    # Create Message table
    Repo.query!("""
    CREATE TABLE IF NOT EXISTS messages (
      id INTEGER PRIMARY KEY,
      content TEXT NOT NULL,
      message_type TEXT NOT NULL DEFAULT 'text',
      file_path TEXT,
      file_name TEXT,
      file_size INTEGER,
      file_type TEXT,
      user_id INTEGER NOT NULL REFERENCES users(id),
      room_id INTEGER NOT NULL REFERENCES rooms(id),
      inserted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
    """)
    
    # Create Categories table
    Repo.query!("""
    CREATE TABLE IF NOT EXISTS categories (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      slug TEXT NOT NULL UNIQUE,
      description TEXT,
      parent_id INTEGER REFERENCES categories(id),
      inserted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
    """)
    
    # Create Articles table
    Repo.query!("""
    CREATE TABLE IF NOT EXISTS articles (
      id INTEGER PRIMARY KEY,
      title TEXT NOT NULL,
      slug TEXT NOT NULL UNIQUE,
      content TEXT NOT NULL,
      summary TEXT,
      category_id INTEGER REFERENCES categories(id),
      inserted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
    """)
  end
  
  @doc """
  Drops all tables for a clean slate.
  """
  def drop do
    Repo.query!("DROP TABLE IF EXISTS articles")
    Repo.query!("DROP TABLE IF EXISTS categories")
    Repo.query!("DROP TABLE IF EXISTS messages")
    Repo.query!("DROP TABLE IF EXISTS user_rooms")
    Repo.query!("DROP TABLE IF EXISTS rooms")
    Repo.query!("DROP TABLE IF EXISTS users")
  end
end