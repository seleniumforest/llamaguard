import features/ban_language
import gleam/erlang/process
import gleam/io
import gleam/option.{None, Some}
import gleeunit/should
import infra/storage/user_chat as uc_repo
import models/cached
import models/chat_settings
import models/user_chat
import setup.{type TestSetup}
import telega/bot
import telega/model/types
import telega/testing/context
import telega/testing/factory
import telega/update

pub fn ban_language_test() {
  io.print("--- ban_language_test --- \n")
  io.print("[NO BAN] random user sends normal message\n")
  call([], False, fn(s) { s.text_msg_from_random_user }, True, [])

  io.print("[NO BAN] random user on quarantine sends normal message\n")
  call([], True, fn(s) { s.text_msg_from_random_user }, True, [])

  io.print("[BAN] random user on quarantine sends restricted symbols\n")
  call(
    ["Han"],
    True,
    fn(s) { with_text(s.text_msg_from_random_user, "汉字") },
    False,
    [
      "deleteMessage",
      "banChatMember",
    ],
  )
  io.print("[NO BAN] random user sends restricted symbols after quarantine\n")
  call(
    ["Han"],
    False,
    fn(s) { with_text(s.text_msg_from_random_user, "汉字") },
    True,
    [],
  )

  io.print("[NO BAN] chat sends normal message\n")
  call([], False, fn(s) { s.text_msg_from_chat }, True, [])

  io.print("[BAN] chat sends restricted symbols\n")
  call(["Han"], False, fn(s) { with_text(s.text_msg_from_chat, "汉字") }, True, [
    "banChatSenderChat",
    "deleteMessage",
  ])

  io.print("[NO BAN] linked channel sends restricted message\n")
  call(
    ["Han"],
    False,
    fn(s) { with_text(s.forwarded_post_from_channel, "汉字") },
    True,
    [],
  )

  io.print("[NO BAN] trusted user sends restricted message\n")
  call(
    ["Han"],
    False,
    fn(s) { with_text(s.text_msg_from_trusted_user, "汉字") },
    True,
    [],
  )
  io.print("[BAN] non-member sends restricted symbols\n")
  call(
    ["Han"],
    False,
    fn(s) { with_text(s.comment_from_usersender, "somerestrictedshit汉字") },
    True,
    [
      "deleteMessage",
      "banChatMember",
    ],
  )
}

fn call(
  banned_languages: List(String),
  on_quarantine: Bool,
  upd: fn(TestSetup) -> types.Update,
  should_call_nextfn: Bool,
  expected_calls: List(String),
) {
  let s = setup.get_setup()

  let #(client, calls) = s.mocked_client
  let config = context.config_with_client(client)
  let upd = upd(s)
  let update = update.raw_to_update(upd)
  let settings =
    chat_settings.ChatSettings(
      ..s.session.chat_settings,
      banned_languages:,
      linked_channel_id: cached.Cached(1, -1_002_821_928_697),
    )

  case on_quarantine {
    True -> {
      let _ =
        uc_repo.create_user_chat(
          s.session.db,
          7_985_173_553,
          -1_003_519_676_531,
          user_chat.UserChat(1, [], True, "", ""),
        )
      Nil
    }
    False -> Nil
  }

  let ctx =
    bot.Context(
      key: "test_chat:123",
      update:,
      config:,
      session: s.session,
      chat_subject: process.new_subject(),
      start_time: None,
      log_prefix: None,
      bot_info: factory.bot_user(),
    )
    |> setup.with_middlewares(update, s)
    |> setup.with_settings(settings)

  ban_language.checker(ctx, update, fn(_, _) {
    should.be_true(should_call_nextfn)
  })

  setup.cmp_calls(calls, expected_calls)
}

fn with_text(upd: types.Update, text: String) {
  case upd.message {
    Some(msg) ->
      types.Update(..upd, message: Some(types.Message(..msg, text: Some(text))))
    None -> panic as "couldn't set msg text"
  }
}
