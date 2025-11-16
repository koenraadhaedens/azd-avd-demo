@description('Environment name for resource naming')
param environmentName string

@description('Location for resources')
param location string

@description('Resource tags')
param tags object

// Create User Assigned Managed Identity for deployment scripts
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-deployment-${environmentName}'
  location: location
  tags: tags
}

// Note: Azure AD role assignments for managed identities typically need to be done manually
// or through Microsoft Graph API as they require tenant-level permissions that may not be
// available during Bicep deployment. Consider running these commands after deployment:
//
// # Get the managed identity principal ID
// $principalId = "<principal-id-from-output>"
// 
// # Connect to Microsoft Graph
// Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory"
// 
// # Assign User Administrator role
// $userAdminRole = Get-MgDirectoryRole | Where-Object {$_.DisplayName -eq "User Administrator"}
// if (-not $userAdminRole) {
//     $userAdminRoleTemplate = Get-MgDirectoryRoleTemplate | Where-Object {$_.DisplayName -eq "User Administrator"}
//     $userAdminRole = New-MgDirectoryRole -RoleTemplateId $userAdminRoleTemplate.Id
// }
// New-MgDirectoryRoleMember -DirectoryRoleId $userAdminRole.Id -BodyParameter @{"@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$principalId"}

// Output the identity information
output identityId string = userAssignedIdentity.id
output identityName string = userAssignedIdentity.name
output principalId string = userAssignedIdentity.properties.principalId
output clientId string = userAssignedIdentity.properties.clientId
