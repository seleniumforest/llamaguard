import gleam/io
import gleeunit/should
import infra/handle
import infra/storage/kvstorage
import models/bot_session

pub fn should_check_test() {
  io.print("--- should_check test --- \n")
  let s = bot_session.default(kvstorage.init("file::memory:"))
  let should_called = fn() { Nil }
  let should_not_called = fn() { should.fail() }

  handle.apply_to_targets(
    session: s,
    trusted_senders: False,
    non_members: True,
    newcomers: True,
    chatsenders: True,
    next: should_called,
    checker: should_not_called,
  )

  handle.apply_to_targets(
    session: bot_session.BotSession(..s, is_trusted_sender: True),
    trusted_senders: False,
    non_members: True,
    newcomers: True,
    chatsenders: True,
    next: should_called,
    checker: should_not_called,
  )

  handle.apply_to_targets(
    session: bot_session.BotSession(..s, is_sender_non_member: fn() { True }),
    trusted_senders: False,
    non_members: True,
    newcomers: False,
    chatsenders: False,
    next: should_not_called,
    checker: should_called,
  )

  handle.apply_to_targets(
    session: bot_session.BotSession(..s, is_sender_non_member: fn() { True }),
    trusted_senders: False,
    non_members: True,
    newcomers: False,
    chatsenders: False,
    next: should_not_called,
    checker: should_called,
  )

  handle.apply_to_targets(
    session: bot_session.BotSession(..s, is_sender_on_quarantine: True),
    trusted_senders: False,
    non_members: False,
    newcomers: True,
    chatsenders: False,
    next: should_not_called,
    checker: should_called,
  )

  handle.apply_to_targets(
    session: bot_session.BotSession(..s, is_sender_a_chat: True),
    trusted_senders: False,
    non_members: False,
    newcomers: False,
    chatsenders: True,
    next: should_not_called,
    checker: should_called,
  )

  handle.apply_to_targets(
    session: bot_session.BotSession(
      ..s,
      is_sender_a_chat: True,
      is_trusted_sender: True,
    ),
    trusted_senders: False,
    non_members: False,
    newcomers: False,
    chatsenders: True,
    next: should_called,
    checker: should_not_called,
  )

  handle.apply_to_targets(
    session: bot_session.BotSession(..s, is_sender_on_quarantine: True),
    trusted_senders: False,
    non_members: True,
    newcomers: True,
    chatsenders: True,
    next: should_not_called,
    checker: should_called,
  )
}
