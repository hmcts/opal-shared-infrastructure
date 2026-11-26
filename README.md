# Opal Shared Infrastructure
This repository contains the shared common infrastructure components for Opal ?!

Generate a local environment report or schedule a daily Teams update with the
[environment report tool](bin/environment-report/README.md).

## Reference-data Service Bus access

Each environment's Opal managed identity has Data Sender on its reference-data topic
and Data Receiver on its reference-data subscription. Existing topic-module Sender
grants are preserved; `servicebus_topic_sender_object_id` records an existing
principal when it differs from CSDS, avoiding replacement or duplicate Opal grants.
Developer-group Receiver access is managed separately.

For retained previews, configure `servicebus_preview_reference_data_access` in the
owning environment's tfvars with the existing topic and subscription ARM IDs. This
manages only the Opal MI's scoped Sender and Receiver grants, not the ASO-managed
entities. Leave the map empty for environments without retained previews. Remove
each entry and apply the role removal before retiring its preview.

## PostgreSQL DB Writer role

`DTS JIT Access opal DB Writer SC` is an Entra group, mirrored as a database role by the
`terraform-module-postgresql-flexible` module. It exists in production only
(`enable_write_group_access = var.env == "prod"`). Access is requested through the
"Database - Opal production DB write access" package in `azure-access-packages`: 2 hours,
approved by `DTS Opal Database Access Approvers`. Connect with the group name as the
database user and your own Entra token as the password - see details in the terraform-module-postgres-flexible repo readme for further instructions.

In each Opal database, in the `public` schema, the role has:

- `USAGE` on the schema
- `SELECT`, `INSERT`, `UPDATE`, `DELETE` on tables
- `USAGE`, `SELECT`, `UPDATE` on sequences

It has no `CREATE`, `TRUNCATE`, `REFERENCES` or `TRIGGER`, and does not own any objects.
