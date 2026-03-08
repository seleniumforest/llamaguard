-module(unicode_ffi).
-export([normalize_nfkd/1]).

normalize_nfkd(String) ->
    Bin = unicode:characters_to_nfkd_binary(String),
    Invisible = [
        <<16#FE0F/utf8>>,
        <<16#FE0E/utf8>>,
        <<16#200B/utf8>>,
        <<16#200C/utf8>>,
        <<16#200D/utf8>>,
        <<16#2060/utf8>>,
        <<16#FEFF/utf8>>
    ],
    lists:foldl(
        fun(Char, Acc) -> binary:replace(Acc, Char, <<>>, [global]) end,
        Bin,
        Invisible
    ).
