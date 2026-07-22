// import features/ban_channels
// import features/cas
// import features/trust_user
// import gleam/dynamic/decode
// import gleam/erlang/process
// import gleam/http/response
// import gleam/int
// import gleam/json
// import gleam/list
// import gleam/option.{Some}
// import gleam/set
// import gleam/string
// import gleeunit/should
// import infra/alias.{type BotContext}
// import infra/storage/kvstorage
// import middlewares/dependencies
// import middlewares/inject_context
// import middlewares/newcomers_events
// import middlewares/resources
// import middlewares/setup_permissions
// import models/bot_session
// import models/chat_settings
// import simplifile
// import telega/bot.{Context}
// import telega/client
// import telega/model/decoder
// import telega/model/types.{type Chat, type User}
// import telega/testing/context
// import telega/testing/handler
// import telega/testing/mock
// import telega/update

// pub fn ban_channels_test() {
//   let setup = get_setup()

//   let call = fn(
//     ban_channels: Bool,
//     upd: update.Update,
//     should_call_nextfn: Bool,
//     expected_calls: List(String),
//   ) {
//     handler.test_handler(
//       session: bot_session.BotSession(
//         ..setup.session,
//         chat_settings: chat_settings.ChatSettings(
//           ..setup.session.chat_settings,
//           ban_channels:,
//         ),
//       ),
//       update: upd,
//       handler: fn(ctx, upd) {
//         let ctx =
//           ctx
//           |> with_fake_client(setup.mocked_client.0)
//           |> with_fake_deps(bot_session.Deps(cas_check: fn(_) { False }))
//         let assert Ok(ctx) = apply_middlewares(setup, ctx, upd)

//         ban_channels.checker(
//           with_fake_client(ctx, setup.mocked_client.0),
//           upd,
//           fn(_, _) { should.be_true(should_call_nextfn) },
//         )

//         Ok(ctx)
//       },
//     )

//     cmp_calls(setup.mocked_client.1, expected_calls)
//   }

//   [
//     #(False, setup.text_msg_from_user, True, []),
//     #(False, setup.text_msg_from_chat, True, []),
//     #(True, setup.text_msg_from_user, True, []),
//     #(True, setup.text_msg_from_chat, False, [
//       "deleteMessage",
//       "banChatSenderChat",
//     ]),
//   ]
//   |> list.each(fn(x) { call(x.0, update.raw_to_update(x.1), x.2, x.3) })
// }

// pub fn cas_test() {
//   let setup = get_setup()

//   let call = fn(
//     cas_enabled: Bool,
//     upd: update.Update,
//     should_call_nextfn: Bool,
//     cas_check_result: Bool,
//     expected_calls: List(String),
//   ) {
//     handler.test_handler(
//       session: bot_session.BotSession(
//         ..setup.session,
//         chat_settings: chat_settings.ChatSettings(
//           ..setup.session.chat_settings,
//           cas_enabled:,
//         ),
//       ),
//       update: upd,
//       handler: fn(ctx, upd) {
//         let ctx =
//           ctx
//           |> with_fake_client(setup.mocked_client.0)
//           |> with_fake_deps(
//             bot_session.Deps(cas_check: fn(_) { cas_check_result }),
//           )
//         let assert Ok(ctx) = apply_middlewares(setup, ctx, upd)

//         cas.checker(ctx, upd, fn(_, _) { should.be_true(should_call_nextfn) })

//         Ok(ctx)
//       },
//     )

//     cmp_calls(setup.mocked_client.1, expected_calls)
//   }

//   [
//     //setting on with positive
//     #(True, setup.text_msg_from_user, True, True, ["banChatMember"]),
//     #(True, setup.user_joined, True, True, ["banChatMember"]),
//     //setting on with negative
//     #(True, setup.text_msg_from_user, True, False, []),
//     #(True, setup.user_joined, True, False, []),
//     //setting off
//     #(False, setup.user_joined, True, False, []),
//     #(False, setup.text_msg_from_user, True, True, []),
//     #(False, setup.user_joined, True, True, []),
//   ]
//   |> list.each(fn(x) { call(x.0, update.raw_to_update(x.1), x.2, x.3, x.4) })
// }

// pub fn trust_user_test() {
//   let setup = get_setup()

//   let call = fn(
//     trusted_users: List(String),
//     upd: update.Update,
//     should_call_nextfn: Bool,
//   ) {
//     handler.test_handler(
//       session: bot_session.BotSession(
//         ..setup.session,
//         chat_settings: chat_settings.ChatSettings(
//           ..setup.session.chat_settings,
//           trusted_users:,
//         ),
//       ),
//       update: upd,
//       handler: fn(ctx, upd) {
//         let ctx =
//           ctx
//           |> with_fake_client(setup.mocked_client.0)
//           |> with_fake_deps(bot_session.Deps(cas_check: fn(_) { False }))

//         let assert Ok(ctx) = apply_middlewares(setup, ctx, upd)
//         trust_user.checker(ctx, upd, fn(_, _) {
//           should.be_true(should_call_nextfn)
//         })

//         Ok(ctx)
//       },
//     )
//   }

//   [
//     #([], setup.text_msg_from_user, True),
//     #([int.to_string(setup.usersender.id)], setup.text_msg_from_user, False),
//   ]
//   |> list.each(fn(x) { call(x.0, update.raw_to_update(x.1), x.2) })
// }
