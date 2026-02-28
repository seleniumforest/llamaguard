# Telegram @llamaguard_bot

## Llamas act as effective, natural guardians for alpacas by utilizing their territorial, assertive behavior to deter predators like coyotes, foxes, and loose dogs.

A Telegram moderation bot written in Gleam (targeting the Erlang VM). Still not a complete anti-spam solution, but can be used with other bots' captcha/anti-spam features.

## Requirements

- Erlang/OTP 27+
- rebar3
- cheapest 1gb/1cpu vps

## Install Erlang and Gleam

https://gleam.run/getting-started/installing/

## Configuration

Make a `cp .env.example .env` and provide bot token.

## Running the bot

Run `gleam run` or `./run_with_log.sh` - it makes live stdout log into app.log and restarts after failure

## Bot commands (for chat administrators)

use `/help` or `/start` in a private chat

## Resources

- Resource files used by the bot are in the `res/` directory. Ensure these are present:
  - `res/female_names.txt`
  - `res/female_names_rus.txt`

These lists are used by the female-name check feature.

## Contributing

If you'd like to make a PR, please:
- Ensure you saved dependency structure: models <- infra <- features/middlewares <- bot
- Try to avoid unnecessary identation (let code grow vertically). Use bool.guard, result.try etc.

## License

```
            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
                    Version 2, December 2004

 Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>

 Everyone is permitted to copy and distribute verbatim or modified
 copies of this license document, and changing it is allowed as long
 as the name is changed.

            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

  0. You just DO WHAT THE FUCK YOU WANT TO.
```
