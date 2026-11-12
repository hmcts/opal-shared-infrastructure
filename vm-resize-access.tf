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
  count = var.env == "test" && var.perf_test_vm_resizers_group_object_id != null ? 2 : 0

  scope              = data.azurerm_virtual_machine.perf_test[count.index].id
  role_definition_id = azurerm_role_definition.perf_test_vm_resizer[0].role_definition_resource_id
  principal_id       = var.perf_test_vm_resizers_group_object_id
}
