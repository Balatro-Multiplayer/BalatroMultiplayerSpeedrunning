-- Authoritative client-side lobby kind. Every entry path (create / join / queue / practice)
-- sets SPDRN._lobby_kind before the lobby view is built, so UI and start logic never have to
-- wait on async metadata.
function SPDRN.get_lobby_kind()
	return SPDRN._lobby_kind or SPDRN.LobbyKind.PRIVATE
end

function SPDRN.is_matchmaking(kind)
	kind = kind or SPDRN.get_lobby_kind()
	return kind == SPDRN.LobbyKind.RANKED or kind == SPDRN.LobbyKind.CASUAL
end
