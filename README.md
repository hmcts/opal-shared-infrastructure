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
