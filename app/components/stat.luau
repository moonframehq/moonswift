-- A small labelled number. Shared with `use "stat"`; the inspector points at
-- the line of the mod that used it.
return component {
	title = "Stat",
	build = function(props)
		return ui.column {
			class = "stat",
			gap = "small",
			grow = true,
			ui.text { props.label, class = "muted", size = "small" },
			ui.text { tostring(props.value), weight = "semibold", numeric = true },
		}
	end,
}
