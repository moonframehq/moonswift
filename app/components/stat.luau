-- A small labelled number. Shared with `use "stat"`; the inspector points at
-- the line of the mod that used it.
return function(props)
	return ui.column {
		class = "stat",
		gap = 2,
		grow = props.grow,
		ui.text { props.label, class = "muted", size = 11 },
		ui.text { tostring(props.value), weight = "semibold", numeric = true },
	}
end
