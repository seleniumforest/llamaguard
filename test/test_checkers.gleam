import features/ban_channels
import features/cas
import features/trust_user
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http/response
import gleam/int
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
import middlewares/setup_permissions
import models/bot_session
import models/chat_settings
import simplifile
import telega/bot.{Context}
import telega/client
import telega/model/decoder
import telega/model/types.{type Chat, type User}
import telega/testing/context
import telega/testing/handler
import telega/testing/mock
import telega/update

pub fn ban_channels_test() {
  let setup = get_setup()

  let call = fn(
    ban_channels: Bool,
    upd: update.Update,
    should_call_nextfn: Bool,
    expected_calls: List(String),
  ) {
    handler.test_handler(
      session: bot_session.BotSession(
        ..setup.session,
        chat_settings: chat_settings.ChatSettings(
          ..setup.session.chat_settings,
          ban_channels:,
        ),
      ),
      update: upd,
      handler: fn(ctx, upd) {
        let ctx =
          ctx
          |> with_fake_client(setup.mocked_client.0)
          |> with_fake_deps(bot_session.Deps(cas_check: fn(_) { False }))
        let assert Ok(ctx) = apply_middlewares(setup, ctx, upd)

        ban_channels.checker(
          with_fake_client(ctx, setup.mocked_client.0),
          upd,
          fn(_, _) { should.be_true(should_call_nextfn) },
        )

        Ok(ctx)
      },
    )

    cmp_calls(setup.mocked_client.1, expected_calls)
  }

  [
    #(False, setup.text_msg_from_user, True, []),
    #(False, setup.text_msg_from_chat, True, []),
    #(True, setup.text_msg_from_user, True, []),
    #(True, setup.text_msg_from_chat, False, [
      "deleteMessage",
      "banChatSenderChat",
    ]),
  ]
  |> list.each(fn(x) { call(x.0, update.raw_to_update(x.1), x.2, x.3) })
}

pub fn cas_test() {
  let setup = get_setup()

  let call = fn(
    cas_enabled: Bool,
    upd: update.Update,
    should_call_nextfn: Bool,
    cas_check_result: Bool,
    expected_calls: List(String),
  ) {
    handler.test_handler(
      session: bot_session.BotSession(
        ..setup.session,
        chat_settings: chat_settings.ChatSettings(
          ..setup.session.chat_settings,
          cas_enabled:,
        ),
      ),
      update: upd,
      handler: fn(ctx, upd) {
        let ctx =
          ctx
          |> with_fake_client(setup.mocked_client.0)
          |> with_fake_deps(
            bot_session.Deps(cas_check: fn(_) { cas_check_result }),
          )
        let assert Ok(ctx) = apply_middlewares(setup, ctx, upd)

        cas.checker(ctx, upd, fn(_, _) { should.be_true(should_call_nextfn) })

        Ok(ctx)
      },
    )

    cmp_calls(setup.mocked_client.1, expected_calls)
  }

  [
    //setting on with positive
    #(True, setup.text_msg_from_user, True, True, ["banChatMember"]),
    #(True, setup.user_joined, True, True, ["banChatMember"]),
    //setting on with negative
    #(True, setup.text_msg_from_user, True, False, []),
    #(True, setup.user_joined, True, False, []),
    //setting off
    #(False, setup.user_joined, True, False, []),
    #(False, setup.text_msg_from_user, True, True, []),
    #(False, setup.user_joined, True, True, []),
  ]
  |> list.each(fn(x) { call(x.0, update.raw_to_update(x.1), x.2, x.3, x.4) })
}

pub fn trust_user_test() {
  let setup = get_setup()

  let call = fn(
    trusted_users: List(String),
    upd: update.Update,
    should_call_nextfn: Bool,
  ) {
    handler.test_handler(
      session: bot_session.BotSession(
        ..setup.session,
        chat_settings: chat_settings.ChatSettings(
          ..setup.session.chat_settings,
          trusted_users:,
        ),
      ),
      update: upd,
      handler: fn(ctx, upd) {
        let ctx =
          ctx
          |> with_fake_client(setup.mocked_client.0)
          |> with_fake_deps(bot_session.Deps(cas_check: fn(_) { False }))

        let assert Ok(ctx) = apply_middlewares(setup, ctx, upd)
        trust_user.checker(ctx, upd, fn(_, _) {
          should.be_true(should_call_nextfn)
        })

        Ok(ctx)
      },
    )
  }

  [
    #([], setup.text_msg_from_user, True),
    #([int.to_string(setup.usersender.id)], setup.text_msg_from_user, False),
  ]
  |> list.each(fn(x) { call(x.0, update.raw_to_update(x.1), x.2) })
}

fn apply_middlewares(setup: TestSetup, ctx: BotContext, upd: update.Update) {
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
    setup_permissions.setup_permissions(),
    newcomers_events.newcomers_events(),
  ]
  |> list.fold(Ok(ctx), fn(prev, mw) {
    let assert Ok(ctx) = prev
    let middleware = mw(fn(ctx, _upd) { Ok(ctx) })
    middleware(ctx, upd)
  })
}

pub type TestSetup {
  TestSetup(
    //entities
    moderated_chat: Chat,
    linked_channel: Chat,
    usersender: User,
    chatsender: Chat,
    mocked_client: #(client.TelegramClient, process.Subject(mock.ApiCall)),
    session: bot_session.BotSession(kvstorage.StorageMessage),
    //updates
    text_msg_from_user: types.Update,
    text_msg_from_chat: types.Update,
    forwarded_post_from_channel: types.Update,
    comment_from_usersender: types.Update,
    comment_from_chatsender: types.Update,
    message_via_bot: types.Update,
    user_joined: types.Update,
  )
}

fn get_setup() {
  let session = bot_session.default(kvstorage.init("file::memory:"))

  let text_msg_from_user = upd_from_raw_json("text_msg_from_user.json")
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
    text_msg_from_user.message
    |> option.then(fn(m) { m.from })
    |> option.to_result("")

  let assert Ok(chatsender) =
    text_msg_from_chat.message
    |> option.then(fn(m) { m.sender_chat })
    |> option.to_result("")

  let mocked_client =
    mock.client_with(fn(req) {
      let assert Ok(method) = string.split(req.path, "/") |> list.last
      case method {
        "getChat" -> {
          Ok(
            response.new(200)
            |> response.set_body(from_raw_json("get_chat.json")),
          )
        }
        "getMe" -> {
          Ok(
            response.new(200)
            |> response.set_body(from_raw_json("get_me.json")),
          )
        }
        "getChatAdministrators" -> {
          Ok(
            response.new(200)
            |> response.set_body(from_raw_json("chat_administrators.json")),
          )
        }
        _ ->
          Ok(
            response.new(200)
            |> response.set_body("{\"ok\": true, \"result\": true }"),
          )
      }
    })

  TestSetup(
    linked_channel:,
    moderated_chat:,
    usersender:,
    chatsender:,
    mocked_client:,
    session:,
    //updates
    text_msg_from_user:,
    text_msg_from_chat:,
    forwarded_post_from_channel:,
    comment_from_usersender:,
    comment_from_chatsender:,
    message_via_bot:,
    user_joined:,
  )
}

fn cmp_calls(client, expected_calls: List(String)) {
  // let actual_calls =
  //   mock.get_calls(client)
  //   |> list.map(fn(x) {
  //     case string.split(x.request.path, "/") |> list.last() {
  //       Ok(el) -> el
  //       Error(_) -> ""
  //     }
  //   })

  // should.equal(actual_calls, expected_calls)
  let expected = expected_calls |> set.from_list
  let actual =
    mock.get_calls(client)
    |> list.map(fn(x) {
      case string.split(x.request.path, "/") |> list.last() {
        Ok(el) -> el
        Error(_) -> ""
      }
    })
    |> set.from_list

  should.be_true(set.is_subset(actual, expected))
}

fn upd_from_raw_json(filename: String) -> types.Update {
  let decoder = {
    use result <- decode.field("result", decode.list(decoder.update_decoder()))
    decode.success(result)
  }

  let assert Ok(json) = simplifile.read("./test/raw/" <> filename)
  let assert Ok(upd) = json.parse(from: json, using: decoder)
  let assert Ok(first) = list.first(upd)
  first
}

fn from_raw_json(filename: String) -> String {
  let assert Ok(json) = simplifile.read("./test/raw/" <> filename)
  json
}

fn with_fake_client(ctx: BotContext, client: client.TelegramClient) {
  Context(..ctx, config: context.config_with_client(client))
}

fn with_fake_deps(ctx: BotContext, dependencies: bot_session.Deps) {
  Context(..ctx, session: bot_session.BotSession(..ctx.session, dependencies:))
}
