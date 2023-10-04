# Initialize tokens and endpoints
$hubspot_app_token = "" ## Use your token
$aws_token = "" ## Use your token
$hubspot_contacts_endpoint = "https://api.hubapi.com/crm/v3/objects/contacts"
$aws_address = "" ## Use your aws endpoint

# Prepare headers for HubSpot and AWS API calls
$hubspot_data_headers = @{"Authorization" = $("Bearer " + $hubspot_app_token)}
$aws_data_headers = @{"Authorization" = $("Bearer " + $aws_token)}

# Fetch existing contacts from HubSpot and AWS
$get_crm_contact_data = Invoke-RestMethod $hubspot_contacts_endpoint -Headers $hubspot_data_headers
$get_aws_data = (Invoke-RestMethod $aws_address -Headers $aws_data_headers) | Sort id

# Transform AWS data to match HubSpot schema
$transformed_data = foreach ($record in $get_aws_data) {
    [PSCustomObject]@{
        email = $record.email
        phone = $record.phone_number
        firstname = $record.first_name
        lastname = $record.last_name
    }
}

# Separate transformed data based on email presence
$transformed_data_excluding_empty_email = $transformed_data.Where({ ![string]::IsNullOrWhiteSpace($_.email) })
$transformed_data_with_empty_email = $transformed_data.Where({ [string]::IsNullOrWhiteSpace($_.email) })

# Initialize arrays for existing users and users to create
$existing_users = @()
$users_to_create = @()

# Identify existing users and users to create based on email
foreach ($record_with_email in $transformed_data_excluding_empty_email) {
    $matching_record = $get_crm_contact_data.results.where({ $_.properties.email -eq $record_with_email.email})
    if ($matching_record) {
        $existing_users +=  $record_with_email
    } else {
        $users_to_create += $record_with_email
    }
}    

# Identify existing users and users to create based on name
foreach ($record_without_email in $transformed_data_with_empty_email) {
    $matching_record_by_name = $get_crm_contact_data.results.Where({
        $_.properties.firstname -eq $record_without_email.firstname -and
        $_.properties.lastname -eq $record_without_email.lastname
    })
    if ($matching_record_by_name) {
        $existing_users += $record_without_email
    } else {
        $users_to_create += $record_without_email
    }
}

# Array to store results of create requests
$create_request_results = @()

# Iterate through users to create and send POST requests to HubSpot
foreach ($user in $users_to_create) {
    # Initialize payload, explicitly checking each property for null or empty values
    $properties_to_create = @{}
    if (![string]::IsNullOrWhiteSpace($user.email)) {
        $properties_to_create.Add("email", $user.email)
    }
    if (![string]::IsNullOrWhiteSpace($user.phone)) {
        $properties_to_create.Add("phone", $user.phone)
    }
    if (![string]::IsNullOrWhiteSpace($user.firstname)) {
        $properties_to_create.Add("firstname", $user.firstname)
    }
    if (![string]::IsNullOrWhiteSpace($user.lastname)) {
        $properties_to_create.Add("lastname", $user.lastname)
    }

    $user_payload = @{
        properties = $properties_to_create
    } | ConvertTo-Json

    # Send POST request to create user
    try {
        $create_user = Invoke-RestMethod -Uri $hubspot_contacts_endpoint -Method Post -Headers $hubspot_data_headers -Body $user_payload -ContentType 'application/json'
        $status = "Success"
    } catch {
        $status = "Fail"
    }

    # Store the result in the array
    $create_request_results += [PSCustomObject]@{
        email     = $user.email
        firstname = $user.firstname
        lastname  = $user.lastname
        status    = $status
    }

    Start-Sleep -Milliseconds 250
}

# Array to store results of update requests
$update_request_results = @()

# Iterate through existing users to update them in HubSpot
foreach ($existing_user in $existing_users) {
    # Initialize user_id as an empty string
    $user_id = ""

    # Find the corresponding user ID based on email, if email is not null
    if (![string]::IsNullOrWhiteSpace($existing_user.email)) {
        $user_id = ($get_crm_contact_data.results.Where({ $_.properties.email -eq $existing_user.email })).id
    }

    # If user_id is still empty, try finding it based on firstname and lastname
    if ($user_id -eq "") {
        $user_id = ($get_crm_contact_data.results.Where({ $_.properties.firstname -eq $existing_user.firstname -and $_.properties.lastname -eq $existing_user.lastname })).id
    }

    # Skip the loop iteration if the user ID is not found
    if ($user_id -eq "") {
        continue
    }

    # Initialize payload, explicitly checking each property for null or empty values
    $properties_to_update = @{}
    if (![string]::IsNullOrWhiteSpace($existing_user.email)) {
        $properties_to_update.Add("email", $existing_user.email)
    }
    if (![string]::IsNullOrWhiteSpace($existing_user.phone)) {
        $properties_to_update.Add("phone", $existing_user.phone)
    }
    if (![string]::IsNullOrWhiteSpace($existing_user.firstname)) {
        $properties_to_update.Add("firstname", $existing_user.firstname)
    }
    if (![string]::IsNullOrWhiteSpace($existing_user.lastname)) {
        $properties_to_update.Add("lastname", $existing_user.lastname)
    }

    $user_payload = @{
        properties = $properties_to_update
    } | ConvertTo-Json

    # Send PATCH request to update user
    try {
        $update_user = Invoke-RestMethod -Uri "$hubspot_contacts_endpoint/$user_id" -Method Patch -Headers $hubspot_data_headers -Body $user_payload -ContentType 'application/json'
        $status = "Success"
    } catch {
        $status = "Fail"
    }

    # Store the result in the array
    $update_request_results += [PSCustomObject]@{
        id        = $user_id
        email     = $existing_user.email
        firstname = $existing_user.firstname
        lastname  = $existing_user.lastname
        status    = $status
    }

    Start-Sleep -Milliseconds 250
}
