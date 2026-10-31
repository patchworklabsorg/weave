# frozen_string_literal: true

# == Route Map
#
# Routes for application:
#                                       Prefix Verb   URI Pattern                                                                                       Controller#Action
#                   native_oauth_authorization GET    /oauth/authorize/native(.:format)                                                                 oauth/authorizations#show
#                          oauth_authorization GET    /oauth/authorize(.:format)                                                                        oauth/authorizations#new
#                                              DELETE /oauth/authorize(.:format)                                                                        oauth/authorizations#destroy
#                                              POST   /oauth/authorize(.:format)                                                                        oauth/authorizations#create
#                                  oauth_token POST   /oauth/token(.:format)                                                                            oauth/tokens#create
#                                 oauth_revoke POST   /oauth/revoke(.:format)                                                                           oauth/tokens#revoke
#                             oauth_introspect POST   /oauth/introspect(.:format)                                                                       oauth/tokens#introspect
#                           oauth_applications GET    /oauth/applications(.:format)                                                                     doorkeeper/applications#index
#                                              POST   /oauth/applications(.:format)                                                                     doorkeeper/applications#create
#                        new_oauth_application GET    /oauth/applications/new(.:format)                                                                 doorkeeper/applications#new
#                       edit_oauth_application GET    /oauth/applications/:id/edit(.:format)                                                            doorkeeper/applications#edit
#                            oauth_application GET    /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#show
#                                              PATCH  /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#update
#                                              PUT    /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#update
#                                              DELETE /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#destroy
#                oauth_authorized_applications GET    /oauth/authorized_applications(.:format)                                                          doorkeeper/authorized_applications#index
#                 oauth_authorized_application DELETE /oauth/authorized_applications/:id(.:format)                                                      doorkeeper/authorized_applications#destroy
#                             oauth_token_info GET    /oauth/token/info(.:format)                                                                       doorkeeper/token_info#show
#                                    webfinger GET    /.well-known/webfinger(.:format)                                                                  oauth/webfinger#show
#                         oauth_discovery_keys GET    /oauth/discovery/keys(.:format)                                                                   doorkeeper/openid_connect/discovery#keys
#                     oauth_discovery_provider GET    /.well-known/openid-configuration(.:format)                                                       doorkeeper/openid_connect/discovery#provider
#                                              GET    /.well-known/oauth-authorization-server(.:format)                                                 doorkeeper/openid_connect/discovery#provider
#                    oauth_discovery_webfinger GET    /.well-known/webfinger(.:format)                                                                  doorkeeper/openid_connect/discovery#webfinger
#                               oauth_userinfo GET    /oauth/userinfo(.:format)                                                                         oauth/userinfo#show
#                         oauth_oauth_metadata GET    /oauth/.well-known/oauth-authorization-server(.:format)                                           oauth/discovery#oauth_authorization_server
#                   oauth_openid_configuration GET    /oauth/.well-known/openid-configuration(.:format)                                                 doorkeeper/openid_connect/discovery#provider
#                                              GET    /(*path)                                                                                          redirect(302)
#                                         root GET    /                                                                                                 home#index
#      accept_code_of_conduct_slack_onboarding POST   /slack/code-of-conduct(.:format)                                                                  slack_onboarding#accept_code_of_conduct
#                      status_slack_onboarding GET    /slack/status(.:format)                                                                           slack_onboarding#status
#                             slack_onboarding GET    /slack(.:format)                                                                                  slack_onboarding#show
#                                              POST   /slack(.:format)                                                                                  slack_onboarding#create
#                                     birthday POST   /slack/birthday(.:format)                                                                         birthdays#create
#              resend_guardian_consent_request POST   /guardian-consent/resend(.:format)                                                                guardian_consent_requests#resend
#                     guardian_consent_request GET    /guardian-consent(.:format)                                                                       guardian_consent_requests#show
#                                              POST   /guardian-consent(.:format)                                                                       guardian_consent_requests#create
#                             guardian_consent GET    /guardian/:token(.:format)                                                                        guardian_consents#show
#                                              POST   /guardian/:token(.:format)                                                                        guardian_consents#create
#                                              DELETE /guardian/:token(.:format)                                                                        guardian_consents#destroy
#          not_resident_verification_residency POST   /verification/residency/not_resident(.:format)                                                    residency_checks#not_resident
#                       verification_residency POST   /verification/residency(.:format)                                                                 residency_checks#create
#                                 verification GET    /verification(.:format)                                                                           verifications#show
#                                              POST   /verification(.:format)                                                                           verifications#create
#                                              GET    /.well-known/*path                                                                                well_known#show
#                                              GET    /security.txt(.:format)                                                                           redirect(301, /.well-known/security.txt)
#                                       signup GET    /signup(.:format)                                                                                 users#new
#                                              POST   /signup(.:format)                                                                                 users#create
#                            username_conflict GET    /signup/username-conflict(.:format)                                                               users#username_conflict
#                                        login GET    /login(.:format)                                                                                  auth#new_session
#                                  oauth_login GET    /oauth/login(.:format)                                                                            auth#oauth_login
#                                              POST   /login(.:format)                                                                                  auth#login
#                              send_magic_link POST   /auth/magic_link(.:format)                                                                        auth#send_magic_link
#                             magic_link_login GET    /auth/magic_link/:token(.:format)                                                                 auth#magic_link_login
#                           confirm_magic_link POST   /auth/magic_link/:token(.:format)                                                                 auth#confirm_magic_link
#                         check_password_login POST   /auth/check_password_login(.:format)                                                              auth#check_password_login
#                      passkey_sign_in_options POST   /auth/passkey/options(.:format)                                                                   auth#passkey_options
#                              passkey_sign_in POST   /auth/passkey(.:format)                                                                           auth#passkey_login
#                                       logout DELETE /logout(.:format)                                                                                 auth#logout
#                                           me GET    /auth/me(.:format)                                                                                auth#me
#                                     password GET    /password(.:format)                                                                               passwords#show
#                                              PATCH  /password(.:format)                                                                               passwords#update
#                             expired_password GET    /password/expired(.:format)                                                                       expired_passwords#show
#                             password_expired PATCH  /password/expired(.:format)                                                                       expired_passwords#update
#                                      profile GET    /profile(.:format)                                                                                users#show
#                                 edit_profile GET    /profile/edit(.:format)                                                                           users#edit
#                             profile_sessions GET    /profile/sessions(.:format)                                                                       users#sessions
#                         destroy_all_sessions DELETE /profile/sessions(.:format)                                                                       users#destroy_all_sessions
#                                      session DELETE /profile/sessions/:id(.:format)                                                                   users#destroy_session
#                               update_profile PATCH  /profile(.:format)                                                                                users#update
#                                 demographics GET    /profile/demographics(.:format)                                                                   demographics#show
#                                              PATCH  /profile/demographics(.:format)                                                                   demographics#update
#                                              PUT    /profile/demographics(.:format)                                                                   demographics#update
#                                              DELETE /profile/demographics(.:format)                                                                   demographics#destroy
#                              funder_consents POST   /profile/funder_consents(.:format)                                                                funder_consents#create
#                               funder_consent DELETE /profile/funder_consents/:funder(.:format)                                                        funder_consents#destroy
#                                      takeout GET    /profile/export(.:format)                                                                         takeouts#show
#                                              POST   /profile/export(.:format)                                                                         takeouts#create
#                             download_takeout GET    /profile/export/:id/download(.:format)                                                            takeouts#download
#                             deletion_request GET    /profile/delete(.:format)                                                                         deletion_requests#show
#                                              DELETE /profile/delete(.:format)                                                                         deletion_requests#destroy
#                                              POST   /profile/delete(.:format)                                                                         deletion_requests#create
#                           email_confirmation GET    /email_confirmation(.:format)                                                                     email_confirmations#show
#                                confirm_email GET    /confirm_email/:token(.:format)                                                                   email_confirmations#confirm
#                    resend_email_confirmation POST   /email_confirmation/resend(.:format)                                                              email_confirmations#resend
#                   make_primary_email_address PATCH  /profile/emails/:id/make_primary(.:format)                                                        email_addresses#make_primary
#            resend_confirmation_email_address POST   /profile/emails/:id/resend_confirmation(.:format)                                                 email_addresses#resend_confirmation
#                              email_addresses POST   /profile/emails(.:format)                                                                         email_addresses#create
#                                email_address DELETE /profile/emails/:id(.:format)                                                                     email_addresses#destroy
#                        confirm_email_address GET    /emails/confirm/:token(.:format)                                                                  email_addresses#confirm
#                             options_passkeys POST   /profile/passkeys/options(.:format)                                                               passkeys#options
#                                     passkeys GET    /profile/passkeys(.:format)                                                                       passkeys#index
#                                              POST   /profile/passkeys(.:format)                                                                       passkeys#create
#                                      passkey DELETE /profile/passkeys/:id(.:format)                                                                   passkeys#destroy
#                              social_profiles GET    /profile/social(.:format)                                                                         social_profiles#index
#                               social_profile DELETE /profile/social/:id(.:format)                                                                     social_profiles#destroy
#                      social_profile_callback GET    /auth/:provider/callback(.:format)                                                                social_profiles#create {provider: /github/}
#                       social_profile_failure GET    /auth/failure(.:format)                                                                           social_profiles#failure
#                           user_profile_photo GET    /user/:p_id/pfp(.:format)                                                                         profile_photos#show
#                                  user_avatar GET    /user/:p_id/avatar/:variant(.:format)                                                             profile_photos#avatar
#                           user_avatar_square GET    /user/:p_id/avatar/:variant/square(.:format)                                                      profile_photos#avatar_square
#                           user_avatar_circle GET    /user/:p_id/avatar/:variant/circle(.:format)                                                      profile_photos#avatar_circle
#                                user_initials GET    /user/:p_id/initials(/:variant)(.:format)                                                         profile_photos#initials {format: :svg}
#                         user_initials_circle GET    /user/:p_id/initials/:variant/circle(.:format)                                                    profile_photos#initials_circle {format: :svg}
#                           rails_health_check GET    /up(.:format)                                                                                     rails/health#show
#                                  ok_computer        /ok                                                                                               OkComputer::Engine
#               stop_impersonating_admin_users DELETE /admin/users/stop_impersonating(.:format)                                                         admin/users#stop_impersonating
#       start_pre_review_identity_verification PATCH  /identity/verifications/:id/start_pre_review(.:format)                                            identity/verifications#start_pre_review
#   take_over_pre_review_identity_verification PATCH  /identity/verifications/:id/take_over_pre_review(.:format)                                        identity/verifications#take_over_pre_review
#                  image_identity_verification POST   /identity/verifications/:id/image(.:format)                                                       identity/verifications#image
#        reject_document_identity_verification PATCH  /identity/verifications/:id/reject_document(.:format)                                             identity/verifications#reject_document
#       approve_document_identity_verification PATCH  /identity/verifications/:id/approve_document(.:format)                                            identity/verifications#approve_document
#          schedule_call_identity_verification PATCH  /identity/verifications/:id/schedule_call(.:format)                                               identity/verifications#schedule_call
#                 decide_identity_verification PATCH  /identity/verifications/:id/decide(.:format)                                                      identity/verifications#decide
#     resolve_escalation_identity_verification PATCH  /identity/verifications/:id/resolve_escalation(.:format)                                          identity/verifications#resolve_escalation
#        residency_image_identity_verification POST   /identity/verifications/:id/residency_image(.:format)                                             identity/verifications#residency_image
#    identity_verification_break_glass_records POST   /identity/verifications/:verification_id/break_glass_records(.:format)                            identity/break_glass_records#create
#                       identity_verifications GET    /identity/verifications(.:format)                                                                 identity/verifications#index
#                        identity_verification GET    /identity/verifications/:id(.:format)                                                             identity/verifications#show
#    start_pre_review_identity_residency_check PATCH  /identity/residency_checks/:id/start_pre_review(.:format)                                         identity/residency_checks#start_pre_review
#               image_identity_residency_check POST   /identity/residency_checks/:id/image(.:format)                                                    identity/residency_checks#image
#     reject_document_identity_residency_check PATCH  /identity/residency_checks/:id/reject_document(.:format)                                          identity/residency_checks#reject_document
#              decide_identity_residency_check PATCH  /identity/residency_checks/:id/decide(.:format)                                                   identity/residency_checks#decide
#                    identity_residency_checks GET    /identity/residency_checks(.:format)                                                              identity/residency_checks#index
#                     identity_residency_check GET    /identity/residency_checks/:id(.:format)                                                          identity/residency_checks#show
# approval_options_identity_break_glass_record POST   /identity/break_glass_records/:id/approval_options(.:format)                                      identity/break_glass_records#approval_options
#          approve_identity_break_glass_record PATCH  /identity/break_glass_records/:id/approve(.:format)                                               identity/break_glass_records#approve
#             deny_identity_break_glass_record PATCH  /identity/break_glass_records/:id/deny(.:format)                                                  identity/break_glass_records#deny
#             open_identity_break_glass_record POST   /identity/break_glass_records/:id/open(.:format)                                                  identity/break_glass_records#open
#                 identity_break_glass_records GET    /identity/break_glass_records(.:format)                                                           identity/break_glass_records#index
#            delay_identity_break_glass_notice PATCH  /identity/break_glass_notices/:id/delay(.:format)                                                 identity/break_glass_notices#delay
#   sign_off_delay_identity_break_glass_notice PATCH  /identity/break_glass_notices/:id/sign_off_delay(.:format)                                        identity/break_glass_notices#sign_off_delay
#       lift_delay_identity_break_glass_notice PATCH  /identity/break_glass_notices/:id/lift_delay(.:format)                                            identity/break_glass_notices#lift_delay
#                          identity_governance GET    /identity/governance(.:format)                                                                    identity/governance#show
#         approve_identity_governance_proposal PATCH  /identity/governance_proposals/:id/approve(.:format)                                              identity/governance_proposals#approve
#          reject_identity_governance_proposal PATCH  /identity/governance_proposals/:id/reject(.:format)                                               identity/governance_proposals#reject
#        withdraw_identity_governance_proposal PATCH  /identity/governance_proposals/:id/withdraw(.:format)                                             identity/governance_proposals#withdraw
#                identity_governance_proposals POST   /identity/governance_proposals(.:format)                                                          identity/governance_proposals#create
#                 identity_governance_proposal GET    /identity/governance_proposals/:id(.:format)                                                      identity/governance_proposals#show
#                       identity_team_removals POST   /identity/team_removals(.:format)                                                                 identity/team_removals#create
#                         identity_key_custody GET    /identity/key_custody(.:format)                                                                   identity/key_custody#show
#               options_identity_hardware_keys POST   /identity/hardware_keys/options(.:format)                                                         identity/hardware_keys#options
#                 revoke_identity_hardware_key PATCH  /identity/hardware_keys/:id/revoke(.:format)                                                      identity/hardware_keys#revoke
#       seal_key_options_identity_hardware_key POST   /identity/hardware_keys/:id/seal_key_options(.:format)                                            identity/hardware_keys#seal_key_options
#               seal_key_identity_hardware_key POST   /identity/hardware_keys/:id/seal_key(.:format)                                                    identity/hardware_keys#seal_key
#         rewrap_options_identity_hardware_key POST   /identity/hardware_keys/:id/rewrap_options(.:format)                                              identity/hardware_keys#rewrap_options
#                 rewrap_identity_hardware_key POST   /identity/hardware_keys/:id/rewrap(.:format)                                                      identity/hardware_keys#rewrap
#                       identity_hardware_keys POST   /identity/hardware_keys(.:format)                                                                 identity/hardware_keys#create
#                  start_identity_key_ceremony POST   /identity/key_ceremony/start(.:format)                                                            identity/key_ceremonies#start
#                    new_identity_key_ceremony GET    /identity/key_ceremony/new(.:format)                                                              identity/key_ceremonies#new
#                        identity_key_ceremony POST   /identity/key_ceremony(.:format)                                                                  identity/key_ceremonies#create
#          activation_options_identity_key_set POST   /identity/key_sets/:id/activation_options(.:format)                                               identity/key_sets#activation_options
#                    activate_identity_key_set POST   /identity/key_sets/:id/activate(.:format)                                                         identity/key_sets#activate
#                     discard_identity_key_set PATCH  /identity/key_sets/:id/discard(.:format)                                                          identity/key_sets#discard
#                                   admin_root GET    /admin(.:format)                                                                                  admin/dashboard#index
#                                 admin_search GET    /admin/search(.:format)                                                                           admin/search#index {format: :json}
#                       impersonate_admin_user POST   /admin/users/:id/impersonate(.:format)                                                            admin/users#impersonate
#                         regen_pid_admin_user PATCH  /admin/users/:id/regen_pid(.:format)                                                              admin/users#regen_pid
#                   invite_to_slack_admin_user POST   /admin/users/:id/invite_to_slack(.:format)                                                        admin/users#invite_to_slack
#         code_of_conduct_exemption_admin_user PATCH  /admin/users/:id/code_of_conduct_exemption(.:format)                                              admin/users#code_of_conduct_exemption
#                     admin_user_impersonation GET    /admin/users/:user_id/impersonations/:id(.:format)                                                admin/user_impersonations#show
#           resend_admin_user_guardian_consent POST   /admin/users/:user_id/guardian_consents/:id/resend(.:format)                                      admin/user_guardian_consents#resend
#           revoke_admin_user_guardian_consent PATCH  /admin/users/:user_id/guardian_consents/:id/revoke(.:format)                                      admin/user_guardian_consents#revoke
#           verify_admin_user_guardian_consent PATCH  /admin/users/:user_id/guardian_consents/:id/verify(.:format)                                      admin/user_guardian_consents#verify
#                 admin_user_guardian_consents POST   /admin/users/:user_id/guardian_consents(.:format)                                                 admin/user_guardian_consents#create
#           override_admin_user_program_grants POST   /admin/users/:user_id/program_grants/override(.:format)                                           admin/user_program_grants#override
#                    admin_user_program_grants POST   /admin/users/:user_id/program_grants(.:format)                                                    admin/user_program_grants#create
#                      admin_user_thread_count GET    /admin/users/:user_id/thread_count(.:format)                                                      admin/user_thread_counts#show
#        reverse_admin_user_thread_count_entry PATCH  /admin/users/:user_id/thread_count_entries/:id/reverse(.:format)                                  admin/user_thread_count_entries#reverse
#              admin_user_thread_count_entries POST   /admin/users/:user_id/thread_count_entries(.:format)                                              admin/user_thread_count_entries#create
#                                  admin_users GET    /admin/users(.:format)                                                                            admin/users#index
#                                              POST   /admin/users(.:format)                                                                            admin/users#create
#                               new_admin_user GET    /admin/users/new(.:format)                                                                        admin/users#new
#                              edit_admin_user GET    /admin/users/:id/edit(.:format)                                                                   admin/users#edit
#                                   admin_user GET    /admin/users/:id(.:format)                                                                        admin/users#show
#                                              PATCH  /admin/users/:id(.:format)                                                                        admin/users#update
#                                              PUT    /admin/users/:id(.:format)                                                                        admin/users#update
#                revoke_admin_role_assignments POST   /admin/role_assignments/revoke(.:format)                                                          admin/role_assignments#revoke
#                       admin_role_assignments GET    /admin/role_assignments(.:format)                                                                 admin/role_assignments#index
#                                              POST   /admin/role_assignments(.:format)                                                                 admin/role_assignments#create
#                 request_blacklist_admin_knot POST   /admin/knots/:id/request_blacklist(.:format)                                                      admin/knots#request_blacklist
#               request_name_change_admin_knot POST   /admin/knots/:id/request_name_change(.:format)                                                    admin/knots#request_name_change
#                                  admin_knots GET    /admin/knots(.:format)                                                                            admin/knots#index
#                                   admin_knot GET    /admin/knots/:id(.:format)                                                                        admin/knots#show
#           sign_off_admin_knot_change_request PATCH  /admin/knot_change_requests/:id/sign_off(.:format)                                                admin/knot_change_requests#sign_off
#            decline_admin_knot_change_request PATCH  /admin/knot_change_requests/:id/decline(.:format)                                                 admin/knot_change_requests#decline
#                     admin_break_glass_report GET    /admin/break_glass_report(.:format)                                                               admin/break_glass_reports#show
#                review_admin_guardian_consent PATCH  /admin/guardian_consents/:id/review(.:format)                                                     admin/guardian_consents#review
#                      admin_guardian_consents GET    /admin/guardian_consents(.:format)                                                                admin/guardian_consents#index
#                      admin_group_memberships POST   /admin/groups/:group_id/memberships(.:format)                                                     admin/group_memberships#create
#                       admin_group_membership DELETE /admin/groups/:group_id/memberships/:id(.:format)                                                 admin/group_memberships#destroy
#                                 admin_groups GET    /admin/groups(.:format)                                                                           admin/groups#index
#                                              POST   /admin/groups(.:format)                                                                           admin/groups#create
#                              new_admin_group GET    /admin/groups/new(.:format)                                                                       admin/groups#new
#                             edit_admin_group GET    /admin/groups/:id/edit(.:format)                                                                  admin/groups#edit
#                                  admin_group GET    /admin/groups/:id(.:format)                                                                       admin/groups#show
#                                              PATCH  /admin/groups/:id(.:format)                                                                       admin/groups#update
#                                              PUT    /admin/groups/:id(.:format)                                                                       admin/groups#update
#                                              DELETE /admin/groups/:id(.:format)                                                                       admin/groups#destroy
#                           admin_demographics GET    /admin/demographics(.:format)                                                                     admin/demographics#show
#                         admin_funder_reports GET    /admin/funder_reports(.:format)                                                                   admin/funder_reports#index
#                          admin_funder_report GET    /admin/funder_reports/:funder(.:format)                                                           admin/funder_reports#show
#               approve_admin_deletion_request PATCH  /admin/deletion_requests/:id/approve(.:format)                                                    admin/deletion_requests#approve
#                reject_admin_deletion_request PATCH  /admin/deletion_requests/:id/reject(.:format)                                                     admin/deletion_requests#reject
#                 rerun_admin_deletion_request PATCH  /admin/deletion_requests/:id/rerun(.:format)                                                      admin/deletion_requests#rerun
#                      admin_deletion_requests GET    /admin/deletion_requests(.:format)                                                                admin/deletion_requests#index
#                       admin_deletion_request GET    /admin/deletion_requests/:id(.:format)                                                            admin/deletion_requests#show
#                 admin_delete_time_aggregates GET    /admin/delete_time_aggregates(.:format)                                                           admin/delete_time_aggregates#show
#                       activate_admin_service PATCH  /admin/services/:id/activate(.:format)                                                            admin/services#activate
#                     deactivate_admin_service PATCH  /admin/services/:id/deactivate(.:format)                                                          admin/services#deactivate
#                        suspend_admin_service PATCH  /admin/services/:id/suspend(.:format)                                                             admin/services#suspend
#                     revoke_admin_service_key PATCH  /admin/services/:service_id/keys/:id/revoke(.:format)                                             admin/service_keys#revoke
#                  deprecate_admin_service_key PATCH  /admin/services/:service_id/keys/:id/deprecate(.:format)                                          admin/service_keys#deprecate
#                   activate_admin_service_key PATCH  /admin/services/:service_id/keys/:id/activate(.:format)                                           admin/service_keys#activate
#                           admin_service_keys GET    /admin/services/:service_id/keys(.:format)                                                        admin/service_keys#index
#                                              POST   /admin/services/:service_id/keys(.:format)                                                        admin/service_keys#create
#                        new_admin_service_key GET    /admin/services/:service_id/keys/new(.:format)                                                    admin/service_keys#new
#                       edit_admin_service_key GET    /admin/services/:service_id/keys/:id/edit(.:format)                                               admin/service_keys#edit
#                            admin_service_key GET    /admin/services/:service_id/keys/:id(.:format)                                                    admin/service_keys#show
#                                              PATCH  /admin/services/:service_id/keys/:id(.:format)                                                    admin/service_keys#update
#                                              PUT    /admin/services/:service_id/keys/:id(.:format)                                                    admin/service_keys#update
#                                              DELETE /admin/services/:service_id/keys/:id(.:format)                                                    admin/service_keys#destroy
#               activate_admin_service_webhook PATCH  /admin/services/:service_id/webhooks/:id/activate(.:format)                                       admin/service_webhooks#activate
#             deactivate_admin_service_webhook PATCH  /admin/services/:service_id/webhooks/:id/deactivate(.:format)                                     admin/service_webhooks#deactivate
#                   test_admin_service_webhook POST   /admin/services/:service_id/webhooks/:id/test(.:format)                                           admin/service_webhooks#test
#                       admin_service_webhooks GET    /admin/services/:service_id/webhooks(.:format)                                                    admin/service_webhooks#index
#                                              POST   /admin/services/:service_id/webhooks(.:format)                                                    admin/service_webhooks#create
#                    new_admin_service_webhook GET    /admin/services/:service_id/webhooks/new(.:format)                                                admin/service_webhooks#new
#                   edit_admin_service_webhook GET    /admin/services/:service_id/webhooks/:id/edit(.:format)                                           admin/service_webhooks#edit
#                        admin_service_webhook GET    /admin/services/:service_id/webhooks/:id(.:format)                                                admin/service_webhooks#show
#                                              PATCH  /admin/services/:service_id/webhooks/:id(.:format)                                                admin/service_webhooks#update
#                                              PUT    /admin/services/:service_id/webhooks/:id(.:format)                                                admin/service_webhooks#update
#                                              DELETE /admin/services/:service_id/webhooks/:id(.:format)                                                admin/service_webhooks#destroy
#                               admin_services GET    /admin/services(.:format)                                                                         admin/services#index
#                                              POST   /admin/services(.:format)                                                                         admin/services#create
#                            new_admin_service GET    /admin/services/new(.:format)                                                                     admin/services#new
#                           edit_admin_service GET    /admin/services/:id/edit(.:format)                                                                admin/services#edit
#                                admin_service GET    /admin/services/:id(.:format)                                                                     admin/services#show
#                                              PATCH  /admin/services/:id(.:format)                                                                     admin/services#update
#                                              PUT    /admin/services/:id(.:format)                                                                     admin/services#update
#                                              DELETE /admin/services/:id(.:format)                                                                     admin/services#destroy
#    regenerate_secret_admin_oauth_application PATCH  /admin/oauth_applications/:id/regenerate_secret(.:format)                                         admin/oauth_applications#regenerate_secret
#        access_policy_admin_oauth_application PATCH  /admin/oauth_applications/:id/access_policy(.:format)                                             admin/oauth_applications#access_policy
#      code_of_conduct_admin_oauth_application PATCH  /admin/oauth_applications/:id/code_of_conduct(.:format)                                           admin/oauth_applications#code_of_conduct
#     guardian_consent_admin_oauth_application PATCH  /admin/oauth_applications/:id/guardian_consent(.:format)                                          admin/oauth_applications#guardian_consent
#        email_domains_admin_oauth_application PATCH  /admin/oauth_applications/:id/email_domains(.:format)                                             admin/oauth_applications#email_domains
#         verification_admin_oauth_application PATCH  /admin/oauth_applications/:id/verification(.:format)                                              admin/oauth_applications#verification
#        admin_oauth_application_access_grants POST   /admin/oauth_applications/:oauth_application_id/access_grants(.:format)                           admin/oauth_application_access_grants#create
#         admin_oauth_application_access_grant DELETE /admin/oauth_applications/:oauth_application_id/access_grants/:id(.:format)                       admin/oauth_application_access_grants#destroy
#     admin_oauth_application_role_assignments POST   /admin/oauth_applications/:oauth_application_id/roles/:role_id/assignments(.:format)              admin/oauth_application_role_assignments#create
#      admin_oauth_application_role_assignment DELETE /admin/oauth_applications/:oauth_application_id/roles/:role_id/assignments/:id(.:format)          admin/oauth_application_role_assignments#destroy
#                admin_oauth_application_roles POST   /admin/oauth_applications/:oauth_application_id/roles(.:format)                                   admin/oauth_application_roles#create
#                 admin_oauth_application_role DELETE /admin/oauth_applications/:oauth_application_id/roles/:id(.:format)                               admin/oauth_application_roles#destroy
#                     admin_oauth_applications GET    /admin/oauth_applications(.:format)                                                               admin/oauth_applications#index
#                                              POST   /admin/oauth_applications(.:format)                                                               admin/oauth_applications#create
#                  new_admin_oauth_application GET    /admin/oauth_applications/new(.:format)                                                           admin/oauth_applications#new
#                 edit_admin_oauth_application GET    /admin/oauth_applications/:id/edit(.:format)                                                      admin/oauth_applications#edit
#                      admin_oauth_application GET    /admin/oauth_applications/:id(.:format)                                                           admin/oauth_applications#show
#                                              PATCH  /admin/oauth_applications/:id(.:format)                                                           admin/oauth_applications#update
#                                              PUT    /admin/oauth_applications/:id(.:format)                                                           admin/oauth_applications#update
#                                              DELETE /admin/oauth_applications/:id(.:format)                                                           admin/oauth_applications#destroy
#                  lookup_admin_console_access POST   /admin/console_access/lookup(.:format)                                                            admin/console_access#lookup
#                 confirm_admin_console_access POST   /admin/console_access/confirm(.:format)                                                           admin/console_access#confirm
#                         admin_console_access GET    /admin/console_access(.:format)                                                                   admin/console_access#show
#                   admin_mission_control_jobs        /admin/jobs                                                                                       MissionControl::Jobs::Engine
#                             admin_audits1984        /admin/console                                                                                    Audits1984::Engine
#                                                     /admin/flipper                                                                                    Flipper::UI
#                                 admin_blazer        /admin/blazer                                                                                     Blazer::Engine
#                                        admin GET    /admin(.:format)                                                                                  redirect(301, /login)
#                                              GET    /admin/*path(.:format)                                                                            redirect(301, /login)
#                            letter_opener_web        /letter_opener                                                                                    LetterOpenerWeb::Engine
#                                api_v1_health GET    /api/v1/health(.:format)                                                                          api/v1/health#index
#       api_v1_directory_user_shipping_address GET    /api/v1/directory/users/:user_sub/shipping_address(.:format)                                      api/v1/directory/shipping_addresses#show
#                       api_v1_directory_users GET    /api/v1/directory/users(.:format)                                                                 api/v1/directory/users#index
#                        api_v1_directory_user GET    /api/v1/directory/users/:sub(.:format)                                                            api/v1/directory/users#show
#           api_v1_thread_count_project_events POST   /api/v1/thread_count/project_events(.:format)                                                     api/v1/project_events#create
#                        webhooks_slack_events POST   /webhooks/slack/events(.:format)                                                                  webhooks/slack#events
#                  webhooks_slack_interactions POST   /webhooks/slack/interactions(.:format)                                                            webhooks/slack#interactions
#             turbo_recede_historical_location GET    /recede_historical_location(.:format)                                                             turbo/native/navigation#recede
#             turbo_resume_historical_location GET    /resume_historical_location(.:format)                                                             turbo/native/navigation#resume
#            turbo_refresh_historical_location GET    /refresh_historical_location(.:format)                                                            turbo/native/navigation#refresh
#                rails_postmark_inbound_emails POST   /rails/action_mailbox/postmark/inbound_emails(.:format)                                           action_mailbox/ingresses/postmark/inbound_emails#create
#                   rails_relay_inbound_emails POST   /rails/action_mailbox/relay/inbound_emails(.:format)                                              action_mailbox/ingresses/relay/inbound_emails#create
#                rails_sendgrid_inbound_emails POST   /rails/action_mailbox/sendgrid/inbound_emails(.:format)                                           action_mailbox/ingresses/sendgrid/inbound_emails#create
#          rails_mandrill_inbound_health_check GET    /rails/action_mailbox/mandrill/inbound_emails(.:format)                                           action_mailbox/ingresses/mandrill/inbound_emails#health_check
#                rails_mandrill_inbound_emails POST   /rails/action_mailbox/mandrill/inbound_emails(.:format)                                           action_mailbox/ingresses/mandrill/inbound_emails#create
#                 rails_mailgun_inbound_emails POST   /rails/action_mailbox/mailgun/inbound_emails/mime(.:format)                                       action_mailbox/ingresses/mailgun/inbound_emails#create
#               rails_conductor_inbound_emails GET    /rails/conductor/action_mailbox/inbound_emails(.:format)                                          rails/conductor/action_mailbox/inbound_emails#index
#                                              POST   /rails/conductor/action_mailbox/inbound_emails(.:format)                                          rails/conductor/action_mailbox/inbound_emails#create
#            new_rails_conductor_inbound_email GET    /rails/conductor/action_mailbox/inbound_emails/new(.:format)                                      rails/conductor/action_mailbox/inbound_emails#new
#                rails_conductor_inbound_email GET    /rails/conductor/action_mailbox/inbound_emails/:id(.:format)                                      rails/conductor/action_mailbox/inbound_emails#show
#     new_rails_conductor_inbound_email_source GET    /rails/conductor/action_mailbox/inbound_emails/sources/new(.:format)                              rails/conductor/action_mailbox/inbound_emails/sources#new
#        rails_conductor_inbound_email_sources POST   /rails/conductor/action_mailbox/inbound_emails/sources(.:format)                                  rails/conductor/action_mailbox/inbound_emails/sources#create
#        rails_conductor_inbound_email_reroute POST   /rails/conductor/action_mailbox/:inbound_email_id/reroute(.:format)                               rails/conductor/action_mailbox/reroutes#create
#     rails_conductor_inbound_email_incinerate POST   /rails/conductor/action_mailbox/:inbound_email_id/incinerate(.:format)                            rails/conductor/action_mailbox/incinerates#create
#                           rails_service_blob GET    /rails/active_storage/blobs/redirect/:signed_id/*filename(.:format)                               active_storage/blobs/redirect#show
#                     rails_service_blob_proxy GET    /rails/active_storage/blobs/proxy/:signed_id/*filename(.:format)                                  active_storage/blobs/proxy#show
#                                              GET    /rails/active_storage/blobs/:signed_id/*filename(.:format)                                        active_storage/blobs/redirect#show
#                    rails_blob_representation GET    /rails/active_storage/representations/redirect/:signed_blob_id/:variation_key/*filename(.:format) active_storage/representations/redirect#show
#              rails_blob_representation_proxy GET    /rails/active_storage/representations/proxy/:signed_blob_id/:variation_key/*filename(.:format)    active_storage/representations/proxy#show
#                                              GET    /rails/active_storage/representations/:signed_blob_id/:variation_key/*filename(.:format)          active_storage/representations/redirect#show
#                           rails_disk_service GET    /rails/active_storage/disk/:encoded_key/*filename(.:format)                                       active_storage/disk#show
#                    update_rails_disk_service PUT    /rails/active_storage/disk/:encoded_token(.:format)                                               active_storage/disk#update
#                         rails_direct_uploads POST   /rails/active_storage/direct_uploads(.:format)                                                    active_storage/direct_uploads#create
#                  rails_resend_inbound_emails POST   /rails/action_mailbox/resend/inbound_emails(.:format)                                             action_mailbox/ingresses/resend/inbound_emails#create
#                             actual_db_schema        /rails                                                                                            ActualDbSchema::Engine
#
# Routes for OkComputer::Engine:
#            Prefix Verb        URI Pattern       Controller#Action
#              root GET|OPTIONS /                 ok_computer/ok_computer#show {check: "default"}
# okcomputer_checks GET|OPTIONS /all(.:format)    ok_computer/ok_computer#index
#  okcomputer_check GET|OPTIONS /:check(.:format) ok_computer/ok_computer#show
#
# Routes for MissionControl::Jobs::Engine:
#                      Prefix Verb   URI Pattern                                                    Controller#Action
#     application_queue_pause DELETE /applications/:application_id/queues/:queue_id/pause(.:format) mission_control/jobs/queues/pauses#destroy
#                             POST   /applications/:application_id/queues/:queue_id/pause(.:format) mission_control/jobs/queues/pauses#create
#          application_queues GET    /applications/:application_id/queues(.:format)                 mission_control/jobs/queues#index
#           application_queue GET    /applications/:application_id/queues/:id(.:format)             mission_control/jobs/queues#show
#       application_job_retry POST   /applications/:application_id/jobs/:job_id/retry(.:format)     mission_control/jobs/retries#create
#     application_job_discard POST   /applications/:application_id/jobs/:job_id/discard(.:format)   mission_control/jobs/discards#create
#    application_job_dispatch POST   /applications/:application_id/jobs/:job_id/dispatch(.:format)  mission_control/jobs/dispatches#create
#    application_bulk_retries POST   /applications/:application_id/jobs/bulk_retries(.:format)      mission_control/jobs/bulk_retries#create
#   application_bulk_discards POST   /applications/:application_id/jobs/bulk_discards(.:format)     mission_control/jobs/bulk_discards#create
#             application_job GET    /applications/:application_id/jobs/:id(.:format)               mission_control/jobs/jobs#show
#            application_jobs GET    /applications/:application_id/:status/jobs(.:format)           mission_control/jobs/jobs#index
#         application_workers GET    /applications/:application_id/workers(.:format)                mission_control/jobs/workers#index
#          application_worker GET    /applications/:application_id/workers/:id(.:format)            mission_control/jobs/workers#show
# application_recurring_tasks GET    /applications/:application_id/recurring_tasks(.:format)        mission_control/jobs/recurring_tasks#index
#  application_recurring_task GET    /applications/:application_id/recurring_tasks/:id(.:format)    mission_control/jobs/recurring_tasks#show
#                             PATCH  /applications/:application_id/recurring_tasks/:id(.:format)    mission_control/jobs/recurring_tasks#update
#                             PUT    /applications/:application_id/recurring_tasks/:id(.:format)    mission_control/jobs/recurring_tasks#update
#         application_batches GET    /applications/:application_id/batches(.:format)                mission_control/jobs/batches#index
#           application_batch GET    /applications/:application_id/batches/:id(.:format)            mission_control/jobs/batches#show
#                      queues GET    /queues(.:format)                                              mission_control/jobs/queues#index
#                       queue GET    /queues/:id(.:format)                                          mission_control/jobs/queues#show
#                         job GET    /jobs/:id(.:format)                                            mission_control/jobs/jobs#show
#                        jobs GET    /:status/jobs(.:format)                                        mission_control/jobs/jobs#index
#                        root GET    /                                                              mission_control/jobs/queues#index
#
# Routes for Audits1984::Engine:
#            Prefix Verb  URI Pattern                                Controller#Action
#    session_audits POST  /sessions/:session_id/audits(.:format)     audits1984/audits#create
#     session_audit PATCH /sessions/:session_id/audits/:id(.:format) audits1984/audits#update
#                   PUT   /sessions/:session_id/audits/:id(.:format) audits1984/audits#update
#          sessions GET   /sessions(.:format)                        audits1984/sessions#index
#           session GET   /sessions/:id(.:format)                    audits1984/sessions#show
# filtered_sessions PATCH /filtered_sessions(.:format)               audits1984/filtered_sessions#update
#                   PUT   /filtered_sessions(.:format)               audits1984/filtered_sessions#update
#              root GET   /                                          audits1984/sessions#index
#
# Routes for Blazer::Engine:
#            Prefix Verb   URI Pattern                       Controller#Action
#       run_queries POST   /queries/run(.:format)            blazer/queries#run
#    cancel_queries POST   /queries/cancel(.:format)         blazer/queries#cancel
#     refresh_query POST   /queries/:id/refresh(.:format)    blazer/queries#refresh
#    tables_queries GET    /queries/tables(.:format)         blazer/queries#tables
#    schema_queries GET    /queries/schema(.:format)         blazer/queries#schema
#      docs_queries GET    /queries/docs(.:format)           blazer/queries#docs
#           queries GET    /queries(.:format)                blazer/queries#index
#                   POST   /queries(.:format)                blazer/queries#create
#         new_query GET    /queries/new(.:format)            blazer/queries#new
#        edit_query GET    /queries/:id/edit(.:format)       blazer/queries#edit
#             query GET    /queries/:id(.:format)            blazer/queries#show
#                   PATCH  /queries/:id(.:format)            blazer/queries#update
#                   PUT    /queries/:id(.:format)            blazer/queries#update
#                   DELETE /queries/:id(.:format)            blazer/queries#destroy
#         run_check GET    /checks/:id/run(.:format)         blazer/checks#run
#            checks GET    /checks(.:format)                 blazer/checks#index
#                   POST   /checks(.:format)                 blazer/checks#create
#         new_check GET    /checks/new(.:format)             blazer/checks#new
#        edit_check GET    /checks/:id/edit(.:format)        blazer/checks#edit
#             check PATCH  /checks/:id(.:format)             blazer/checks#update
#                   PUT    /checks/:id(.:format)             blazer/checks#update
#                   DELETE /checks/:id(.:format)             blazer/checks#destroy
# refresh_dashboard POST   /dashboards/:id/refresh(.:format) blazer/dashboards#refresh
#        dashboards POST   /dashboards(.:format)             blazer/dashboards#create
#     new_dashboard GET    /dashboards/new(.:format)         blazer/dashboards#new
#    edit_dashboard GET    /dashboards/:id/edit(.:format)    blazer/dashboards#edit
#         dashboard GET    /dashboards/:id(.:format)         blazer/dashboards#show
#                   PATCH  /dashboards/:id(.:format)         blazer/dashboards#update
#                   PUT    /dashboards/:id(.:format)         blazer/dashboards#update
#                   DELETE /dashboards/:id(.:format)         blazer/dashboards#destroy
#              root GET    /                                 blazer/queries#home
#
# Routes for LetterOpenerWeb::Engine:
#        Prefix Verb URI Pattern                      Controller#Action
#       letters GET  /                                letter_opener_web/letters#index
# clear_letters POST /clear(.:format)                 letter_opener_web/letters#clear
#        letter GET  /:id(/:style)(.:format)          letter_opener_web/letters#show
# delete_letter POST /:id/delete(.:format)            letter_opener_web/letters#destroy
#               GET  /:id/attachments/:file(.:format) letter_opener_web/letters#attachment {file: /[^\/]+/}
#
# Routes for ActualDbSchema::Engine:
#                          Prefix Verb URI Pattern                                Controller#Action
#              rollback_migration POST /migrations/:id/rollback(.:format)         actual_db_schema/migrations#rollback
#               migrate_migration POST /migrations/:id/migrate(.:format)          actual_db_schema/migrations#migrate
#                      migrations GET  /migrations(.:format)                      actual_db_schema/migrations#index
#                       migration GET  /migrations/:id(.:format)                  actual_db_schema/migrations#show
#      rollback_phantom_migration POST /phantom_migrations/:id/rollback(.:format) actual_db_schema/phantom_migrations#rollback
# rollback_all_phantom_migrations POST /phantom_migrations/rollback_all(.:format) actual_db_schema/phantom_migrations#rollback_all
#              phantom_migrations GET  /phantom_migrations(.:format)              actual_db_schema/phantom_migrations#index
#               phantom_migration GET  /phantom_migrations/:id(.:format)          actual_db_schema/phantom_migrations#show
#           delete_broken_version POST /broken_versions/:id/delete(.:format)      actual_db_schema/broken_versions#delete
#      delete_all_broken_versions POST /broken_versions/delete_all(.:format)      actual_db_schema/broken_versions#delete_all
#                 broken_versions GET  /broken_versions(.:format)                 actual_db_schema/broken_versions#index
#                          schema GET  /schema(.:format)                          actual_db_schema/schema#index

require_relative "../lib/admin_constraint"

Rails.application.routes.draw do
  # The authorization endpoint is ours only so that the consent screen can relax
  # `form-action` to the client's registered redirect URI; everything else about
  # it is Doorkeeper's, inherited unchanged, including the views under
  # app/views/doorkeeper/authorizations/ (still found via the parent's view
  # prefixes). See app/controllers/oauth/authorizations_controller.rb.
  use_doorkeeper do
    controllers authorizations: "oauth/authorizations", tokens: "oauth/tokens"
  end

  # OpenID Connect. Mounts, at the spec-mandated locations:
  #   GET /.well-known/openid-configuration       OIDC Discovery
  #   GET /.well-known/oauth-authorization-server
  #   GET /.well-known/webfinger
  #   GET /oauth/discovery/keys                   JWKS (public keys only)
  #
  # These documents are generated from config/initializers/doorkeeper.rb and
  # config/initializers/doorkeeper_openid_connect.rb, so they cannot drift from
  # what the server actually supports.
  #
  # The gem's own /oauth/userinfo is skipped: it hard-requires the `openid`
  # scope, and Weave has served userinfo to `profile` tokens since before OIDC
  # existed here. Ours (below) renders the same claims from the same DSL without
  # breaking those clients.
  #
  # WebFinger is likewise ours, and must be declared BEFORE the mount because
  # the first matching route wins and `skip_controllers` works per controller,
  # not per action — there is no way to drop discovery#webfinger while keeping
  # discovery#provider. See app/controllers/oauth/webfinger_controller.rb.
  get ".well-known/webfinger", to: "oauth/webfinger#show", as: :webfinger

  use_doorkeeper_openid_connect do
    skip_controllers :userinfo
  end

  # OAuth 2.0 endpoints
  namespace :oauth do
    get "userinfo", to: "userinfo#show"

    # OAuth 2.0 Server Metadata (RFC 8414)
    get ".well-known/oauth-authorization-server", to: "discovery#oauth_authorization_server", as: :oauth_metadata

    # Legacy OIDC discovery location. The canonical path is
    # /.well-known/openid-configuration (issuer-relative, per OIDC Discovery 1.0
    # §4) and is mounted above, but Weave advertised this one first so it stays
    # as an alias. Deliberately the gem's controller, not a hand-written twin.
    # Leading "/" escapes the :oauth controller namespace.
    get ".well-known/openid-configuration",
        to: "/doorkeeper/openid_connect/discovery#provider",
        as: :openid_configuration
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # slack.patchworklabs.org is the public "join our Slack" address. It sends
  # everyone to the onboarding page on the canonical host, where the session
  # cookie lives. Declared before `root` because the first matching route wins.
  constraints(host: /\Aslack\./i) do
    get "(*path)", format: false, to: redirect(status: 302) { |_params, _request|
      Rails.application.routes.url_helpers.slack_onboarding_url(**Rails.application.config.action_mailer.default_url_options)
    }
  end

  # Defines the root path route ("/")
  # root "articles#index"
  root "home#index"

  # Joining the Patchwork Labs Slack: shows each person the next step
  # (sign up, accept the invite, accept the code of conduct) and lets them
  # request or resend the invite.
  resource :slack_onboarding, path: "slack", only: [:show, :create], controller: "slack_onboarding" do
    post :accept_code_of_conduct, path: "code-of-conduct"
    get :status
  end

  # A member with no birthday on file adds it, as the first step of joining
  # the Slack (see BirthdaysController).
  post "slack/birthday", to: "birthdays#create", as: :birthday

  # A member under 18 asks a parent or guardian for consent, for the apps
  # that require it (see GuardianConsentFlow and AppAccess).
  resource :guardian_consent_request, path: "guardian-consent", only: [:show, :create] do
    post :resend
  end

  # The page the parent or guardian opens from the email. The token is the
  # proof, so no account is needed.
  get "guardian/:token", to: "guardian_consents#show", as: :guardian_consent
  post "guardian/:token", to: "guardian_consents#create"
  delete "guardian/:token", to: "guardian_consents#destroy"

  # Identity verification for program resources (see VerificationFlow). The
  # member uploads an ID and follows the status here.
  resource :verification, only: [:show, :create] do
    # The US residency check without a call (see ResidencyFlow).
    resource :residency, only: [:create], controller: "residency_checks" do
      post :not_resident
    end
  end

  # Well-known routes for standard compliance
  get ".well-known/*path", to: "well_known#show", format: false
  # Legacy location -> canonical RFC 9116 location
  get "/security.txt", to: redirect("/.well-known/security.txt", status: 301)

  # User registration
  get "/signup", to: "users#new", as: :signup
  post "/signup", to: "users#create"
  get "/signup/username-conflict", to: "users#username_conflict", as: :username_conflict

  # Authentication routes
  get "/login", to: "auth#new_session", as: :login
  get "/oauth/login", to: "auth#oauth_login", as: :oauth_login
  post "/login", to: "auth#login"
  post "/auth/magic_link", to: "auth#send_magic_link", as: :send_magic_link
  # GET only shows the confirmation screen; the POST is what actually signs in,
  # so link-scanning bots can't consume a link on the recipient's behalf.
  get "/auth/magic_link/:token", to: "auth#magic_link_login", as: :magic_link_login
  post "/auth/magic_link/:token", to: "auth#confirm_magic_link", as: :confirm_magic_link
  post "/auth/check_password_login", to: "auth#check_password_login", as: :check_password_login
  post "/auth/passkey/options", to: "auth#passkey_options", as: :passkey_sign_in_options
  post "/auth/passkey", to: "auth#passkey_login", as: :passkey_sign_in
  delete "/logout", to: "auth#logout", as: :logout
  get "/auth/me", to: "auth#me", as: :me

  # Change password. Google Workspace links to /password as the SSO profile's
  # "Change password URL". /password/expired is for an AD password that
  # expired or must change, before sign-in (see ExpiredPasswordsController).
  get "/password", to: "passwords#show", as: :password
  patch "/password", to: "passwords#update"
  get "/password/expired", to: "expired_passwords#show", as: :expired_password
  patch "/password/expired", to: "expired_passwords#update"

  # Profile management routes (requires authentication)
  get "/profile", to: "users#show", as: :profile
  get "/profile/edit", to: "users#edit", as: :edit_profile
  get "/profile/sessions", to: "users#sessions", as: :profile_sessions
  delete "/profile/sessions", to: "users#destroy_all_sessions", as: :destroy_all_sessions
  delete "/profile/sessions/:id", to: "users#destroy_session", as: :session
  patch "/profile", to: "users#update", as: :update_profile

  # The member's self-reported demographics: answer, answer again, or take
  # the answers back. Write-only (see DemographicsVault).
  resource :demographics, path: "profile/demographics", only: [:show, :update, :destroy]
  # Consent to be counted in a funder's report (see FunderConsent).
  resources :funder_consents, path: "profile/funder_consents", param: :funder, only: [:create, :destroy]

  # Data takeout and account deletion (see Takeout and DeletionReview).
  resource :takeout, path: "profile/export", only: [:show, :create]
  get "profile/export/:id/download", to: "takeouts#download", as: :download_takeout
  resource :deletion_request, path: "profile/delete", only: [:show, :create, :destroy]

  # Email confirmation routes
  get "/email_confirmation", to: "email_confirmations#show", as: :email_confirmation
  get "/confirm_email/:token", to: "email_confirmations#confirm", as: :confirm_email
  post "/email_confirmation/resend", to: "email_confirmations#resend", as: :resend_email_confirmation

  # Additional email addresses (multi-email support, one primary per user)
  scope "/profile" do
    resources :email_addresses, path: "emails", only: [:create, :destroy] do
      member do
        patch :make_primary
        post :resend_confirmation
      end
    end
  end
  get "/emails/confirm/:token", to: "email_addresses#confirm", as: :confirm_email_address

  # Passkeys for signing in without an email link (see PasskeysController).
  scope "/profile" do
    resources :passkeys, only: [:index, :create, :destroy] do
      post :options, on: :collection
    end
  end

  # Social profiles (see SocialProfilesController). OmniAuth answers
  # POST /auth/:provider itself and sends the member back to the callback.
  # Keep the provider list in step with SocialProfile::PROVIDERS.
  scope "/profile" do
    resources :social_profiles, path: "social", only: [:index, :destroy]
  end
  get "/auth/:provider/callback", to: "social_profiles#create", as: :social_profile_callback, constraints: { provider: /github/ }
  get "/auth/failure", to: "social_profiles#failure", as: :social_profile_failure

  # Profile photo routes (public, no auth required)
  get "/user/:p_id/pfp", to: "profile_photos#show", as: :user_profile_photo
  get "/user/:p_id/avatar/:variant", to: "profile_photos#avatar", as: :user_avatar
  get "/user/:p_id/avatar/:variant/square", to: "profile_photos#avatar_square", as: :user_avatar_square
  get "/user/:p_id/avatar/:variant/circle", to: "profile_photos#avatar_circle", as: :user_avatar_circle
  get "/user/:p_id/initials(/:variant)", to: "profile_photos#initials", as: :user_initials, defaults: { format: :svg }
  get "/user/:p_id/initials/:variant/circle", to: "profile_photos#initials_circle", as: :user_initials_circle, defaults: { format: :svg }


  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  mount OkComputer::Engine, at: "ok"

  # Stop impersonating route (outside admin constraint)
  namespace :admin do
    resources :users, only: [] do
      collection do
        delete :stop_impersonating
      end
    end
  end

  # The identity area (see Identity::BaseController). Not under /admin: the
  # identity team does not need the admin role, and the admin role alone does
  # not open these pages.
  namespace :identity do
    # Identity verification, for the identity team (see VerificationFlow).
    resources :verifications, only: [:index, :show] do
      member do
        patch :start_pre_review
        patch :take_over_pre_review
        post :image
        patch :reject_document
        patch :approve_document
        patch :schedule_call
        patch :decide
        patch :resolve_escalation
        post :residency_image
      end
      resources :break_glass_records, only: [:create]
    end

    # US residency checks without a call (see ResidencyFlow).
    resources :residency_checks, only: [:index, :show] do
      member do
        patch :start_pre_review
        post :image
        patch :reject_document
        patch :decide
      end
    end

    # Break-glass access to stored ID images (see BreakGlass).
    resources :break_glass_records, only: [:index] do
      member do
        post :approval_options
        patch :approve
        patch :deny
        post :open
      end
    end
    resources :break_glass_notices, only: [] do
      member do
        patch :delay
        patch :sign_off_delay
        patch :lift_delay
      end
    end

    # Identity team governance (see IdentityGovernance): owners, board members
    # and identity team leads.
    resource :governance, controller: "governance", only: [:show]
    resources :governance_proposals, only: [:create, :show] do
      member do
        patch :approve
        patch :reject
        patch :withdraw
      end
    end
    resources :team_removals, only: [:create]

    # Key custody of stored ID images (see KeyCustody): hardware keys, the
    # ceremony, recovery and rotation.
    resource :key_custody, controller: "key_custody", only: [:show]
    resources :hardware_keys, only: [:create] do
      collection { post :options }
      member do
        patch :revoke
        post :seal_key_options
        post :seal_key
        post :rewrap_options
        post :rewrap
      end
    end
    resource :key_ceremony, only: [:new, :create] do
      post :start
    end
    resources :key_sets, only: [] do
      member do
        post :activation_options
        post :activate
        patch :discard
      end
    end
  end

  # Admin namespace with constraint
  constraints AdminConstraint.new do
    namespace :admin do
      # Admin dashboard is the root of the admin namespace
      root to: "dashboard#index"

      # Live results for the ⌘K command bar
      get :search, to: "search#index", defaults: { format: :json }

      # Resources and sub-resources
      # No destroy: accounts are deleted only through a deletion request, which
      # runs the deletion pipeline (DeletionPipeline) and sends the receipt.
      resources :users, except: [:destroy] do
        member do
          post :impersonate
          patch :regen_pid
          post :invite_to_slack
          patch :code_of_conduct_exemption
        end
        resources :impersonations, controller: "user_impersonations", only: [:show]

        # Staging only: set a test state (see StagingTestStates).
        resource :staging_test_state, only: [:update]

        resources :guardian_consents, controller: "user_guardian_consents", only: [:create] do
          member do
            post :resend
            patch :revoke
            patch :verify
          end
        end

        # Program grants on the member's Knot (see KnotGrants).
        resources :program_grants, controller: "user_program_grants", only: [:create] do
          collection do
            post :override
          end
        end

        # Thread Count, the internal trust score (see ThreadCount).
        resource :thread_count, controller: "user_thread_counts", only: [:show]
        resources :thread_count_entries, controller: "user_thread_count_entries", only: [:create] do
          member do
            patch :reverse
          end
        end
      end

      # Roles with an immediate grant rule: staff, contractor, board member
      # (see RoleGrants and config/roles.yml).
      resources :role_assignments, only: [:index, :create] do
        collection { post :revoke }
      end

      # The Knot (see KnotLinker and KnotChanges). The index lists the
      # two-key requests that wait for a sign-off.
      resources :knots, only: [:index, :show] do
        member do
          post :request_blacklist
          post :request_name_change
        end
      end
      resources :knot_change_requests, only: [] do
        member do
          patch :sign_off
          patch :decline
        end
      end

      # The break-glass board report (see BreakGlassReport). The verification
      # pages themselves are in the identity area (/identity), below.
      resource :break_glass_report, only: [:show]

      # Guardian consents with a flag, for an admin to check (see
      # GuardianConsentSignals).
      resources :guardian_consents, only: [:index] do
        member do
          patch :review
        end
      end

      resources :groups do
        resources :memberships, controller: "group_memberships", only: [:create, :destroy]
      end

      # Demographics aggregates for funder reports. Counts only, never a
      # member's answers (see DemographicsReport).
      resource :demographics, only: [:show]
      # A preview of each funder's aggregate report (see FunderReport). No
      # export and no send yet.
      resources :funder_reports, param: :funder, only: [:index, :show]

      # Deletion requests for the identity team to review (see
      # DeletionReview), and the delete-time aggregates (counts only).
      resources :deletion_requests, only: [:index, :show] do
        member do
          patch :approve
          patch :reject
          patch :rerun
        end
      end
      resource :delete_time_aggregates, only: [:show]

      resources :services do
        member do
          patch :activate
          patch :deactivate
          patch :suspend
        end

        resources :keys, controller: "service_keys" do
          member do
            patch :revoke
            patch :deprecate
            patch :activate
          end
        end

        resources :webhooks, controller: "service_webhooks" do
          member do
            patch :activate
            patch :deactivate
            post :test
          end
        end
      end

      resources :oauth_applications do
        member do
          patch :regenerate_secret
          patch :access_policy
          patch :code_of_conduct
          patch :guardian_consent
          patch :email_domains
          patch :verification
        end

        resources :access_grants, controller: "oauth_application_access_grants", only: [:create, :destroy]
        resources :roles, controller: "oauth_application_roles", only: [:create, :destroy] do
          resources :assignments, controller: "oauth_application_role_assignments", only: [:create, :destroy]
        end
      end

      # A person signs their production console in. See docs/CONSOLE_ACCESS.md.
      resource :console_access, only: [:show], controller: "console_access" do
        post :lookup
        post :confirm
      end

      # Mount engines under /admin path
      mount MissionControl::Jobs::Engine, at: "/jobs"
      mount Audits1984::Engine => "/console"
      mount Flipper::UI.app(Flipper) { |builder| builder.use FeatureFlags::UserActorAdapter::UnknownActorRedirect }, at: "/flipper"
      mount Blazer::Engine, at: "/blazer"
    end
  end

  # Fallback redirect if adminconstraint fails
  get "admin", to: redirect("/login")
  get "admin/*path", to: redirect("/login")



  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?


  # API routes
  namespace :api do
    namespace :v1 do
      get "health", to: "health#index"

      namespace :directory do
        resources :users, only: [:index, :show], param: :sub do
          resource :shipping_address, only: :show
        end
      end

      # Project review outcomes for Thread Count, from services such as
      # Krater (see Api::V1::ProjectEventsController).
      post "thread_count/project_events", to: "project_events#create", as: :thread_count_project_events
    end
  end

  # Webhook endpoints (external services, no CSRF/auth)
  namespace :webhooks do
    post "slack/events", to: "slack#events"
    post "slack/interactions", to: "slack#interactions"
  end

  #  # Admin routes
  #  namespace :admin do
  #   resources :users do
  #     member do
  #       post :impersonate
  #     end
  #   end
  # end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker


end
