variable initiative {
  type        = any
  description = "Policy Initiative resource node"
}

variable assignment_scope {
  type        = string
  description = "The scope at which the policy initiative will be assigned. Must be full resource IDs. Changing this forces a new resource to be created"
}

variable assignment_not_scopes {
  type        = list(any)
  description = "A list of the Policy Assignment's excluded scopes. Must be full resource IDs"
  default     = []
}

variable assignment_name {
  type        = string
  description = "The name which should be used for this Policy Assignment, defaults to initiative name. Changing this forces a new Policy Assignment to be created"
  default     = ""
}

variable assignment_display_name {
  type        = string
  description = "The policy assignment display name, defaults to initiative display_name. Changing this forces a new resource to be created"
  default     = ""
}

variable assignment_description {
  type        = string
  description = "A description to use for the Policy Assignment, defaults to initiative description. Changing this forces a new resource to be created"
  default     = ""
}

variable assignment_effect {
  type        = string
  description = "The effect of the policy. Changing this forces a new resource to be created"
  default     = null
}

variable assignment_parameters {
  type        = any
  description = "The policy assignment parameters. Changing this forces a new resource to be created"
  default     = null
}

variable assignment_metadata {
  type        = any
  description = "The optional metadata for the policy assignment."
  default     = null
}

variable assignment_enforcement_mode {
  type        = bool
  description = "Control whether the assignment is enforced"
  default     = true
}

variable assignment_location {
  type        = string
  description = "The Azure location where this policy assignment should exist, required when an Identity is assigned. Defaults to UK South. Changing this forces a new resource to be created"
  default     = "uksouth"
}

variable non_compliance_messages {
  type        = any
  description = "The optional non-compliance message(s). Key/Value pairs map as policy_definition_reference_id = 'content', use null = 'content' to specify the Default non-compliance message for all member definitions."
  default     = {}
}

variable "identity_ids" {
  type        = list(any)
  description = "Optional list of User Managed Identity IDs which should be assigned to the Policy Initiative"
  default     = []
}

variable resource_discovery_mode {
  type        = string
  description = "The way that resources to remediate are discovered. Possible values are ExistingNonCompliant or ReEvaluateCompliance. Defaults to ExistingNonCompliant. Applies to subscription scope and below"
  default     = "ExistingNonCompliant"

  validation {
    condition     = var.resource_discovery_mode == "ExistingNonCompliant" || var.resource_discovery_mode == "ReEvaluateCompliance"
    error_message = "Resource Discovery Mode possible values are: ExistingNonCompliant or ReEvaluateCompliance."
  }
}

variable remediation_scope {
  type        = string
  description = "The scope at which the remediation tasks will be created. Must be full resource IDs. Defaults to the policy assignment scope. Changing this forces a new resource to be created"
  default     = ""
}

variable location_filters {
  type        = list(any)
  description = "Optional list of the resource locations that will be remediated"
  default     = []
}

variable failure_percentage {
  type        = number
  description = "(Optional) A number between 0.0 to 1.0 representing the percentage failure threshold. The remediation will fail if the percentage of failed remediation operations (i.e. failed deployments) exceeds this threshold."
  default     = null
}

variable parallel_deployments {
  type        = number
  description = "(Optional) Determines how many resources to remediate at any given time. Can be used to increase or reduce the pace of the remediation. If not provided, the default parallel deployments value is used."
  default     = null
}

variable resource_count {
  type        = number
  description = "(Optional) Determines the max number of resources that can be remediated by the remediation job. If not provided, the default resource count is used."
  default     = null
}

variable role_definition_ids {
  type        = list(string)
  description = "List of Role definition ID's for the System Assigned Identity. Omit this to use those located in policy definitions. Ignored when using Managed Identities. Changing this forces a new resource to be created"
  default     = []
}

variable role_assignment_scope {
  type        = string
  description = "The scope at which role definition(s) will be assigned, defaults to Policy Assignment Scope. Must be full resource IDs. Ignored when using Managed Identities. Changing this forces a new resource to be created"
  default     = null
}

variable skip_remediation {
  type        = bool
  description = "Should the module skip creation of a remediation task for policies that DeployIfNotExists and Modify"
  default     = false
}

variable skip_role_assignment {
  type        = bool
  description = "Should the module skip creation of role assignment for policies that DeployIfNotExists and Modify"
  default     = false
}

locals {
  # assignment_name will be trimmed if exceeds 24 characters
  assignment_name = try(lower(substr(coalesce(var.assignment_name, var.initiative.name), 0, 24)), "")
  display_name = try(coalesce(var.assignment_display_name, var.initiative.display_name), "")
  description = try(coalesce(var.assignment_description, var.initiative.description), "")
  metadata = jsonencode(try(coalesce(var.assignment_metadata, jsondecode(var.initiative.metadata)), {}))

  # convert assignment parameters to the required assignment structure
  parameter_values = var.assignment_parameters != null ? {
    for key, value in var.assignment_parameters :
    key => merge({ value = value })
  } : null

  # merge effect and parameter_values if specified, will use definition default effects if omitted
  parameters = local.parameter_values != null ? var.assignment_effect != null ? jsonencode(merge(local.parameter_values, { effect = { value = var.assignment_effect } })) : jsonencode(local.parameter_values) : null

  # create the optional non-compliance message content block(s) if present
  non_compliance_message = var.non_compliance_messages != {} ? {
    for reference_id, message in var.non_compliance_messages :
    reference_id => message
  } : {}

  # determine if a managed identity should be created with this assignment
  identity_type = length(try(coalescelist(var.role_definition_ids, try(var.initiative.role_definition_ids, [])), [])) > 0 ? length(var.identity_ids) > 0 ? { type = "UserAssigned" } : { type = "SystemAssigned" } : {}

  # try to use policy definition roles if explicit roles are ommitted
  role_definition_ids = var.skip_role_assignment == false && try(values(local.identity_type)[0], "") == "SystemAssigned" ? try(coalescelist(var.role_definition_ids, try(var.initiative.role_definition_ids, [])), []) : []

  # evaluate policy assignment scope from resource identifier
  assignment_scope = try({
    mg       = length(regexall("(\\/managementGroups\\/)", var.assignment_scope)) > 0 ? 1 : 0,
    sub      = length(split("/", var.assignment_scope)) == 3 ? 1 : 0,
    rg       = length(regexall("(\\/managementGroups\\/)", var.assignment_scope)) < 1 ? length(split("/", var.assignment_scope)) == 5 ? 1 : 0 : 0,
    resource = length(split("/", var.assignment_scope)) >= 6 ? 1 : 0,
  })

  # evaluate remediation scope from resource identifier
  remediation_scope = try(coalesce(var.remediation_scope, var.assignment_scope), "")
  remediate = try({
    mg       = length(regexall("(\\/managementGroups\\/)", local.remediation_scope)) > 0 ? 1 : 0,
    sub      = length(split("/", local.remediation_scope)) == 3 ? 1 : 0,
    rg       = length(regexall("(\\/managementGroups\\/)", local.remediation_scope)) < 1 ? length(split("/", local.remediation_scope)) == 5 ? 1 : 0 : 0,
    resource = length(split("/", local.remediation_scope)) >= 6 ? 1 : 0,
  })

  # retrieve definition references & create a remediation task for policies with DeployIfNotExists and Modify effects
  definitions = var.assignment_enforcement_mode == true && var.skip_remediation == false && length(local.identity_type) > 0 ? try(var.initiative.policy_definition_reference, []) : []
  definition_reference = try({
    mg       = local.remediate.mg > 0 ? local.definitions : []
    sub      = local.remediate.sub > 0 ? local.definitions : []
    rg       = local.remediate.rg > 0 ? local.definitions : []
    resource = local.remediate.resource > 0 ? local.definitions : []
  })

  # evaluate outputs
  assignment = try(
    azurerm_management_group_policy_assignment.set[0],
    azurerm_subscription_policy_assignment.set[0],
    azurerm_resource_group_policy_assignment.set[0],
    azurerm_resource_policy_assignment.set[0],
  "")
  remediation_tasks = try(
    azurerm_management_group_policy_remediation.rem,
    azurerm_subscription_policy_remediation.rem,
    azurerm_resource_group_policy_remediation.rem,
    azurerm_resource_policy_remediation.rem,
  {})
}
