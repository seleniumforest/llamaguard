import gleam/dynamic/decode as dyn_decode
import gleam/json
import models/decode

pub type UserChat {
  UserChat(joined_time: Int, messages: Int, on_quarantine: Bool)
}

pub fn default() {
  UserChat(joined_time: 0, messages: 0, on_quarantine: False)
}

pub fn user_chat_encoder(uc: UserChat) {
  json.object([
    #("joined_time", json.int(uc.joined_time)),
    #("messages", json.int(uc.messages)),
    #("on_quarantine", decode.bool_as_int_encoder(uc.on_quarantine)),
  ])
}

pub fn user_chat_decoder() {
  use joined_time <- decode.int_field("joined_time")
  use messages <- decode.int_field("messages")
  use on_quarantine <- decode.bool_field("on_quarantine")

  dyn_decode.success(UserChat(joined_time:, messages:, on_quarantine:))
}
