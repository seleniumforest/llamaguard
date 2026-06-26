import features/ban_channels
import gleam/erlang/process
import gleam/io
import gleam/option.{None}
import gleeunit/should
import models/chat_settings
import setup.{type TestSetup}
import telega/bot
import telega/model/types
import telega/testing/context
import telega/testing/factory
import telega/update

pub fn ban_channels_test() {
  io.print("--- ban_channels_test --- \n")
  call(False, fn(s) { s.text_msg_from_random_user }, True, [])
  call(False, fn(s) { s.text_msg_from_chat }, True, [])
  call(True, fn(s) { s.text_msg_from_random_user }, True, [])
  call(True, fn(s) { s.forwarded_post_from_channel }, True, [])
  call(True, fn(s) { s.text_msg_from_chat }, False, [
    "deleteMessage",
    "banChatSenderChat",
  ])
}

fn call(
  ban_channels: Bool,
  upd: fn(TestSetup) -> types.Update,
  should_call_nextfn: Bool,
  expected_calls: List(String),
) {
  let s = setup.get_setup()

  let #(client, calls) = s.mocked_client
  let config = context.config_with_client(client)
  let update = update.raw_to_update(upd(s))
  let settings =
    chat_settings.ChatSettings(..s.session.chat_settings, ban_channels:)

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

  ban_channels.checker(ctx, update, fn(_, _) {
    should.be_true(should_call_nextfn)
  })

  setup.cmp_calls(calls, expected_calls)
}
