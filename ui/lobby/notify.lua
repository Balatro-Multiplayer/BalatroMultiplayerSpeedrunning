-- Lightweight in-run toast.
function SPDRN.notify(text)
	if G.STAGE ~= G.STAGES.RUN then
		return
	end
	pcall(function()
		attention_text({
			scale = 0.7,
			text = text,
			hold = 2,
			align = 'cm',
			offset = { x = 0, y = -3.5 },
			major = G.play or G.ROOM_ATTACH,
		})
	end)
end
