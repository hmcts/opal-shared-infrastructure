# Import blocks for adopting existing service-owned PostgreSQL infrastructure
# into opal-shared-infrastructure without pg_dump/restore.
#
# These imports intentionally target the legacy_postgresql module definitions.
# They should be run before removing DB infrastructure from individual service
# repos.
#
# Do not import module.legacy_postgresql[*].random_password.password here.
# The random provider cannot import module override_special metadata, so an
# import block causes a forced random_password replacement in the first plan.
# If preserving existing admin passwords is mandatory, move the random_password
# state from each source app repo into these module addresses before apply.
