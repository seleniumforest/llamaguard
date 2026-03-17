import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/result
import infra/log
import infra/storage/kvstorage.{
  type JsonDbValue, type StorageMessage, Create, Delete, Get, SaveProperty,
}
import models/error.{type BotError, InvalidValueError}
import models/user_chat as uc

pub fn create_user_chat(
  actor: Subject(StorageMessage),
  user_id: Int,
  chat_id: Int,
  user_chat: uc.UserChat,
) {
  let chat =
    user_chat
    |> uc.user_chat_encoder

  let json_data =
    process.call_forever(actor, fn(a) {
      Create(a, build_key(user_id, chat_id), chat)
    })

  unwrap_result_to_userchat(json_data)
}

pub fn get_user_chat(actor: Subject(StorageMessage), user_id: Int, chat_id: Int) {
  let json_data =
    process.call_forever(actor, fn(a) { Get(a, build_key(user_id, chat_id)) })
  unwrap_result_to_userchat(json_data)
}

pub fn delete_user_chat(
  actor: Subject(StorageMessage),
  user_id: Int,
  chat_id: Int,
) {
  process.call_forever(actor, fn(a) { Delete(a, build_key(user_id, chat_id)) })
}

pub fn save_user_chat_property(
  actor: Subject(StorageMessage),
  user_id: Int,
  chat_id: Int,
  prop: String,
  val: JsonDbValue,
) {
  process.call_forever(actor, fn(a) {
    SaveProperty(a, build_key(user_id, chat_id), prop, val)
  })
}

fn build_key(user_id: Int, chat_id: Int) {
  "uc:" <> int.to_string(user_id) <> ":" <> int.to_string(chat_id)
}

fn unwrap_result_to_userchat(
  str_value: Result(String, BotError),
) -> Result(uc.UserChat, BotError) {
  use json <- result.try(str_value)

  json.parse(from: json, using: uc.user_chat_decoder())
  |> result.map_error(fn(e) {
    log.printf("ERROR: Invalid JSON found: \n {0}", [json])
    InvalidValueError(e)
  })
}
