# tf-project-production-archimedes-db-sandbox

This is a Terraform project that will create a copy of the primary database
using a point in time restore. Then it will create another rails server using
the web server ami for Archimedes. When the server comes up all Archimedes
services will be stopped and the database will be reconfigured to point at the
point in time restore. When you are done this will allow you to destroy all the
infrastructure related to setting it up. This will also remove the redis and
email settings for safety reasons.

NOTE: the terraform uses the Terraform Workspace name as a unique suffix for the
RDS and web server instances. To be sure you don't conflict with other sandbox
environments, be sure to `terraform workspace new <some-unique-name>` before you
apply, and double-check the plan to be sure the names created won't conflict.
The standard has been to use the ticket-number of the ticket the request is for.

## Dependencies
* Access to AWS to create and destroy databases and servers
* asdf to version control which version of terraform
* terraform 0.14.4

## Instructions

*Note:* the commands `make destroy` and `make plan` do not make or create any
infrastructure. They just create a plan that must be applied.

### Initial setup
1. make init

### Creating the environment
1. make plan
2. make apply

### Destroying the environment
1. make destroy
2. make apply
