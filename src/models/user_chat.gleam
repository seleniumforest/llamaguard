import gleam/dynamic/decode as dyn_decode
import gleam/json
import models/decode

pub type UserChat {
  UserChat(
    joined_time: Int,
    messages: List(UserMessage),
    on_quarantine: Bool,
    first_name: String,
    last_name: String,
    banned: Bool,
  )
}

pub type UserMessage {
  UserMessage(id: Int, text: String)
}

pub fn default() {
  UserChat(
    joined_time: 0,
    messages: [],
    on_quarantine: False,
    first_name: "",
    last_name: "",
    banned: False,
  )
}

pub fn message_encoder(msg: UserMessage) {
  json.object([
    #("id", json.int(msg.id)),
    #("text", json.string(msg.text)),
  ])
}

pub fn user_chat_encoder(uc: UserChat) {
  json.object([
    #("joined_time", json.int(uc.joined_time)),
    #("messages", json.array(uc.messages, message_encoder)),
    #("on_quarantine", json.bool(uc.on_quarantine)),
    #("first_name", json.string(uc.first_name)),
    #("last_name", json.string(uc.last_name)),
    #("banned", json.bool(uc.banned)),
  ])
}

pub fn user_message_field(
  name: String,
  next: fn(List(UserMessage)) -> dyn_decode.Decoder(a),
) -> dyn_decode.Decoder(a) {
  let um_decoder = {
    use id <- dyn_decode.field("id", dyn_decode.int)
    use text <- dyn_decode.field("text", dyn_decode.string)
    dyn_decode.success(UserMessage(id, text))
  }
  use messages <- dyn_decode.field(name, dyn_decode.list(um_decoder))
  next(messages)
}

pub fn user_chat_decoder() {
  use joined_time <- decode.int_field("joined_time")
  use messages <- user_message_field("messages")
  use on_quarantine <- decode.bool_field("on_quarantine")
  use first_name <- decode.string_field("first_name")
  use last_name <- decode.string_field("last_name")
  use banned <- decode.bool_field("banned")

  dyn_decode.success(UserChat(
    joined_time:,
    messages:,
    on_quarantine:,
    first_name:,
    last_name:,
    banned:,
  ))
}
