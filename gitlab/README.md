# GitLab tools

* [create_gitlab_bot_user.sh](create_gitlab_bot_user.sh) - Create bot user in GitLab and set up SSH key (access pass)
  * calls [gitlab_admin.sh](gitlab_admin.sh)
* [create_gitlab_webhook.sh](create_gitlab_webhook.sh) - Create webhook in GitLab  (access pass)
  * calls [gitlab_admin.sh](gitlab_admin.sh)
* [gitlab_admin.sh](gitlab_admin.sh) - Offers GitLab tool functions
  * Available commands:
    * `add_ssh_key` - Add SSH public key
    * `add_user_to_group` - Add user to group
    * `create_api_token` - Create API token
    * `create_bot_user` - Create GitLab bot user
    * `create_webhook` - Create webhook
* [setup_jenkins_gitlab_integration.sh](setup_jenkins_gitlab_integration.sh) - Setup integration between Jenkins and GitLab
  * does the following:
    * Create bot user in GitLab
    * Add GitLab bot credentials to Jenkins instance
    * Add GitLab JCasC config to Jenkins instance
    * Add bot user to projects bot API
    * Add bot to GitLab group
    * Create webhook
* [setup_gitlab_runner_integration.sh](setup_gitlab_runner_integration.sh) - Setup GitLab bot integration for gitlab runner
  * does the following:
    * Create bot user in GitLab
    * Add bot user to projects bot API
    * Add bot to GitLab group
  * calls:
    * [create_gitlab_bot_user.sh](create_gitlab_bot_user.sh)
    * [gitlab_admin.sh](gitlab_admin.sh)
