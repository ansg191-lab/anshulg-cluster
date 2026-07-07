# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

locals {
  location = "g"

  _family = split("-", var.machine_type)[0]
  arch    = contains(["t2a", "c4a", "n4a", "a4x"], local._family) ? "a" : "x"

  os = substr(var.boot_disk_os, 0, 1)

  hostname = lower(format(
    "%s%s%02d-%sv%s",
    local.location,
    var.role,
    var.index,
    local.arch,
    local.os
  ))

  fqdn = format("%s.%s", local.hostname, var.domain)
}
