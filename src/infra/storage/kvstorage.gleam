import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/json
import gleam/list
import gleam/otp/actor
import models/error.{type BotError, DbConnectionError, EmptyDataError}
import sqlight

pub type StorageMessage {
  Get(reply_with: Subject(Result(String, BotError)), id: String)
  Delete(reply_with: Subject(Result(Bool, BotError)), id: String)
  Create(
    reply_with: Subject(Result(String, BotError)),
    id: String,
    obj: json.Json,
  )
  SaveProperty(
    reply_with: Subject(Result(Bool, BotError)),
    id: String,
    prop: String,
    val: json.Json,
  )
}

pub fn init() -> Subject(StorageMessage) {
  let connection = init_db()

  let assert Ok(actor) =
    actor.new(connection)
    |> actor.on_message(handle_message)
    |> actor.start

  actor.data
}

fn string_decoder() {
  use id <- decode.field(0, decode.string)
  decode.success(id)
}

fn handle_message(
  connection: sqlight.Connection,
  message: StorageMessage,
) -> actor.Next(sqlight.Connection, StorageMessage) {
  case message {
    Get(id:, reply_with:) -> {
      let query =
        sqlight.query(
          "SELECT value FROM data WHERE key = ? LIMIT 1;",
          on: connection,
          with: [sqlight.text(id)],
          expecting: string_decoder(),
        )

      unwrap_query_to_settings(query, reply_with)
      actor.continue(connection)
    }

    SaveProperty(reply_with:, id:, prop:, val:) -> {
      let sql = "UPDATE data 
            SET value = json_set(value, '$." <> prop <> "', json(?)) 
            WHERE key = ?;"

      let serialized = val |> json.to_string |> sqlight.text

      let query =
        sqlight.query(
          sql,
          on: connection,
          with: [serialized, sqlight.text(id)],
          expecting: decode.dynamic,
        )

      case query {
        Error(e) -> process.send(reply_with, Error(DbConnectionError(e)))
        Ok(_) -> process.send(reply_with, Ok(True))
      }

      actor.continue(connection)
    }
    Create(id:, reply_with:, obj:) -> {
      let key = sqlight.text(id)
      let value =
        obj
        |> json.to_string
        |> sqlight.text

      let query =
        "INSERT OR REPLACE INTO data (key, value) values (?, ?) RETURNING value;"
        |> sqlight.query(
          on: connection,
          with: [key, value],
          expecting: string_decoder(),
        )

      unwrap_query_to_settings(query, reply_with)
      actor.continue(connection)
    }
    Delete(reply_with:, id:) -> {
      let key = sqlight.text(id)

      let query =
        "DELETE FROM data WHERE key = ?;"
        |> sqlight.query(
          on: connection,
          with: [key],
          expecting: string_decoder(),
        )

      case query {
        Error(e) -> process.send(reply_with, Error(DbConnectionError(e)))
        Ok(_) -> process.send(reply_with, Ok(True))
      }

      actor.continue(connection)
    }
  }
}

fn unwrap_query_to_settings(
  query: Result(List(String), sqlight.Error),
  reply_with: Subject(Result(String, BotError)),
) {
  case query {
    Error(e) -> process.send(reply_with, Error(DbConnectionError(e)))
    Ok(ls) -> {
      case list.first(ls) {
        Error(_) -> process.send(reply_with, Error(EmptyDataError))
        Ok(json) -> process.send(reply_with, Ok(json))
      }
    }
  }
}

fn init_db() {
  let assert Ok(conn) = sqlight.open("file:data.sqlite3")

  let init_query =
    "CREATE TABLE IF NOT EXISTS data (
      key TEXT PRIMARY KEY,
      value JSON NULL);"

  let assert Ok(Nil) = sqlight.exec(init_query, conn)
  conn
}
