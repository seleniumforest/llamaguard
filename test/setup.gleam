import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/set
import gleam/string
import gleeunit/should
import infra/alias.{type BotContext}
import infra/storage/kvstorage
import middlewares/dependencies
import middlewares/inject_context
import middlewares/newcomers_events
import middlewares/resources
import middlewares/setup_flags
import models/bot_session.{type BotSession}
import simplifile
import telega/bot.{Context}
import telega/client
import telega/model/decoder
import telega/model/types.{type Chat, type User}
import telega/testing/context
import telega/testing/mock
import telega/update

pub type TestSetup {
  TestSetup(
    //entities
    moderated_chat: Chat,
    linked_channel: Chat,
    usersender: User,
    chatsender: Chat,
    mocked_client: #(client.TelegramClient, process.Subject(mock.ApiCall)),
    session: BotSession(kvstorage.StorageMessage),
    //updates
    text_msg_from_trusted_user: types.Update,
    text_msg_from_random_user: types.Update,
    text_msg_from_chat: types.Update,
    forwarded_post_from_channel: types.Update,
    comment_from_usersender: types.Update,
    comment_from_chatsender: types.Update,
    message_via_bot: types.Update,
    user_joined: types.Update,
  )
}

pub fn get_setup() {
  let session = bot_session.default(kvstorage.init("file::memory:"))
  let text_msg_from_trusted_user =
    upd_from_raw_json("text_msg_from_trusted_user.json")
  let text_msg_from_random_user =
    upd_from_raw_json("text_msg_from_random_user.json")
  let text_msg_from_chat = upd_from_raw_json("text_msg_from_chat.json")
  let forwarded_post_from_channel =
    upd_from_raw_json("forwarded_post_from_channel.json")
  let comment_from_usersender = upd_from_raw_json("comment_by_usersender.json")
  let comment_from_chatsender = upd_from_raw_json("comment_by_chatsender.json")
  let message_via_bot = upd_from_raw_json("message_via_bot.json")
  let user_joined = upd_from_raw_json("user_joined.json")

  let assert Ok(linked_channel) =
    forwarded_post_from_channel.message
    |> option.then(fn(m) { m.sender_chat })
    |> option.to_result("")

  let assert Ok(moderated_chat) =
    forwarded_post_from_channel.message
    |> option.then(fn(m) { Some(m.chat) })
    |> option.to_result("")

  let assert Ok(usersender) =
    text_msg_from_random_user.message
    |> option.then(fn(m) { m.from })
    |> option.to_result("")

  let assert Ok(chatsender) =
    text_msg_from_chat.message
    |> option.then(fn(m) { m.sender_chat })
    |> option.to_result("")

  let mocked_client =
    mock.client_with(fn(req) {
      let assert Ok(method) = string.split(req.path, "/") |> list.last

      let content = case method {
        "getChatMember" -> from_raw_json("get_chat_member.json")
        "getChat" -> from_raw_json("get_chat.json")
        "getMe" -> from_raw_json("get_me.json")
        "getChatAdministrators" -> from_raw_json("chat_administrators.json")
        "deleteMessage" | "banChatMember" | "banChatSenderChat" ->
          "{\"ok\": true, \"result\": true }"
        _ -> panic as method
      }

      Ok(
        response.new(200)
        |> response.set_body(content),
      )
    })

  TestSetup(
    linked_channel:,
    moderated_chat:,
    usersender:,
    chatsender:,
    mocked_client:,
    session:,
    //updates
    text_msg_from_trusted_user:,
    text_msg_from_random_user:,
    text_msg_from_chat:,
    forwarded_post_from_channel:,
    comment_from_usersender:,
    comment_from_chatsender:,
    message_via_bot:,
    user_joined:,
  )
}

//const default_calls = ["getChatAdministrators", "getChat"]

pub fn cmp_calls(client, expected: List(String)) {
  // let actual_calls =
  //   mock.get_calls(client)
  //   |> list.map(fn(x) {
  //     case string.split(x.request.path, "/") |> list.last() {
  //       Ok(el) -> el
  //       Error(_) -> ""
  //     }
  //   })
  //   |> set.from_list

  // let expected_calls = expected |> list.append(default_calls) |> set.from_list

  // should.equal(actual_calls, expected_calls)
  let expected = expected |> set.from_list
  let actual =
    mock.get_calls(client)
    |> list.map(fn(x) {
      case string.split(x.request.path, "/") |> list.last() {
        Ok(el) -> el
        Error(_) -> ""
      }
    })
    |> set.from_list
  echo expected
  echo actual
  should.be_true(set.is_subset(expected, actual))
}

pub fn upd_from_raw_json(filename: String) -> types.Update {
  let decoder = {
    use result <- decode.field("result", decode.list(decoder.update_decoder()))
    decode.success(result)
  }

  let assert Ok(json) = simplifile.read("./test/raw/" <> filename)
  let assert Ok(upd) = json.parse(from: json, using: decoder)
  let assert Ok(first) = list.first(upd)
  first
}

pub fn from_raw_json(filename: String) -> String {
  let assert Ok(json) = simplifile.read("./test/raw/" <> filename)
  json
}

pub fn with_fake_client(ctx: BotContext, client: client.TelegramClient) {
  Context(..ctx, config: context.config_with_client(client))
}

pub fn with_fake_deps(ctx: BotContext, dependencies: bot_session.Deps) {
  Context(..ctx, session: bot_session.BotSession(..ctx.session, dependencies:))
}

pub fn with_settings(ctx: BotContext, chat_settings) {
  Context(..ctx, session: bot_session.BotSession(..ctx.session, chat_settings:))
}

pub fn with_userchat(ctx: BotContext, uc) {
  Context(
    ..ctx,
    session: bot_session.BotSession(..ctx.session, user_chat: Some(uc)),
  )
}

pub fn with_middlewares(ctx: BotContext, upd: update.Update, setup: TestSetup) {
  [
    dependencies.inject_dependencies(),
    inject_context.inject_chat_settings(setup.session.db),
    inject_context.inject_user_chat(),
    resources.inject_resources(
      bot_session.Resources(
        female_names: ["Alina", "Adele", "Ana"],
        unicode_script_extensions: ["Han", "Arabic", "Korean"],
      ),
    ),
    setup_flags.setup_flags(),
    newcomers_events.newcomers_events(),
  ]
  |> list.fold(ctx, fn(prev, mw) {
    let middleware = mw(fn(ctx, _upd) { Ok(ctx) })
    let assert Ok(result) = middleware(prev, upd)
    result
  })
}
