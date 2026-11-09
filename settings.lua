data:extend({
  {
    type = "bool-setting",
    name = "wp-sink-last-slot-chests-default-on",
    setting_type = "runtime-global",
    default_value = false,
    order = "a"
  },
  {
    type = "bool-setting",
    name = "wp-sink-last-slot-tanks-default-on",
    setting_type = "runtime-global",
    default_value = false,
    order = "b"
  },
  {
    type = "int-setting",
    name = "wp-sink-last-slot-fluid-headroom",
    setting_type = "runtime-global",
    default_value = 1000,
    minimum_value = 1,
    maximum_value = 1000000,
    order = "c"
  },
  {
    type = "int-setting",
    name = "wp-sink-last-slot-check-interval",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 1,
    maximum_value = 600,
    order = "d"
  }
})
