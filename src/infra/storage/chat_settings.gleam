import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/result
import infra/log
import infra/storage/kvstorage.{
  type JsonDbValue, type StorageMessage, Create, Get, SaveProperty,
}
import models/chat_settings as cs
import models/error.{type BotError, InvalidValueError}

pub fn create_chat_settings(actor: Subject(StorageMessage), chat_id: Int) {
  let default_chat =
    cs.default()
    |> cs.chat_encoder

  let json_data =
    process.call_forever(actor, fn(a) {
      Create(a, int.to_string(chat_id), default_chat)
    })

  unwrap_result_to_chat_settings(json_data)
}

pub fn get_chat(actor: Subject(StorageMessage), chat_id: Int) {
  let json_data =
    process.call_forever(actor, fn(a) { Get(a, int.to_string(chat_id)) })
  unwrap_result_to_chat_settings(json_data)
}

pub fn save_chat_property(
  actor: Subject(StorageMessage),
  id: Int,
  prop: String,
  val: JsonDbValue,
) {
  process.call_forever(actor, fn(a) {
    SaveProperty(a, int.to_string(id), prop, val)
  })
}

fn unwrap_result_to_chat_settings(
  str_value: Result(String, BotError),
) -> Result(cs.ChatSettings, BotError) {
  use json <- result.try(str_value)

  json.parse(from: json, using: cs.chat_decoder())
  |> result.map_error(fn(e) {
    log.printf("ERROR: Invalid JSON found: \n {0}", [json])
    InvalidValueError(e)
  })
}
