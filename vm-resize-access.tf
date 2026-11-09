locals {
  perf_test_vm_resize_users = var.env == "test" ? [
    "Madeleine.Hill@hmcts.net",
    "Ashley.Cooper@hmcts.net",
  ] : []
}

data "azuread_users" "perf_test_vm_resize" {
  count          = length(local.perf_test_vm_resize_users) > 0 ? 1 : 0
  mails          = local.perf_test_vm_resize_users
  ignore_missing = false
}

data "azurerm_virtual_machine" "perf_test" {
  count               = var.env == "test" ? 2 : 0
  name                = "opal-perf-test-vm-${count.index}"
  resource_group_name = azurerm_resource_group.opal_resource_group.name

  depends_on = [module.virtual-machine]
}

# Resize only: no delete, Run Command, or disk/network/extension changes.
resource "azurerm_role_definition" "perf_test_vm_resizer" {
  count       = var.env == "test" ? 1 : 0
  name        = "Opal Perf VM Resizer"
  scope       = azurerm_resource_group.opal_resource_group.id
  description = "Allows resizing (deallocate, resize, start) of the Opal performance test VMs."

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/write",
      "Microsoft.Compute/virtualMachines/deallocate/action",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/restart/action",
      "Microsoft.Compute/virtualMachines/vmSizes/read",
      "Microsoft.Compute/locations/vmSizes/read",
      "Microsoft.Compute/locations/usages/read",
      "Microsoft.Compute/locations/operations/read",
    ]
    not_actions = []
  }

  assignable_scopes = [azurerm_resource_group.opal_resource_group.id]
}

resource "azurerm_role_assignment" "perf_test_vm_resize" {
  for_each = var.env == "test" ? {
    for pair in setproduct(range(2), local.perf_test_vm_resize_users) :
    "${pair[0]}-${pair[1]}" => {
      vm_index = pair[0]
      email    = pair[1]
    }
  } : {}

  scope              = data.azurerm_virtual_machine.perf_test[each.value.vm_index].id
  role_definition_id = azurerm_role_definition.perf_test_vm_resizer[0].role_definition_resource_id
  principal_id       = one([for u in data.azuread_users.perf_test_vm_resize[0].users : u.object_id if lower(u.mail) == lower(each.value.email)])
}
