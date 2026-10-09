# frozen_string_literal: true

# == Route Map
#
# Routes for application:
#                                    Prefix Verb   URI Pattern                                                                                       Controller#Action
#                native_oauth_authorization GET    /oauth/authorize/native(.:format)                                                                 oauth/authorizations#show
#                       oauth_authorization GET    /oauth/authorize(.:format)                                                                        oauth/authorizations#new
#                                           DELETE /oauth/authorize(.:format)                                                                        oauth/authorizations#destroy
#                                           POST   /oauth/authorize(.:format)                                                                        oauth/authorizations#create
#                               oauth_token POST   /oauth/token(.:format)                                                                            oauth/tokens#create
#                              oauth_revoke POST   /oauth/revoke(.:format)                                                                           oauth/tokens#revoke
#                          oauth_introspect POST   /oauth/introspect(.:format)                                                                       oauth/tokens#introspect
#                        oauth_applications GET    /oauth/applications(.:format)                                                                     doorkeeper/applications#index
#                                           POST   /oauth/applications(.:format)                                                                     doorkeeper/applications#create
#                     new_oauth_application GET    /oauth/applications/new(.:format)                                                                 doorkeeper/applications#new
#                    edit_oauth_application GET    /oauth/applications/:id/edit(.:format)                                                            doorkeeper/applications#edit
#                         oauth_application GET    /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#show
#                                           PATCH  /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#update
#                                           PUT    /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#update
#                                           DELETE /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#destroy
#             oauth_authorized_applications GET    /oauth/authorized_applications(.:format)                                                          doorkeeper/authorized_applications#index
#              oauth_authorized_application DELETE /oauth/authorized_applications/:id(.:format)                                                      doorkeeper/authorized_applications#destroy
#                          oauth_token_info GET    /oauth/token/info(.:format)                                                                       doorkeeper/token_info#show
#                                 webfinger GET    /.well-known/webfinger(.:format)                                                                  oauth/webfinger#show
#                      oauth_discovery_keys GET    /oauth/discovery/keys(.:format)                                                                   doorkeeper/openid_connect/discovery#keys
#                  oauth_discovery_provider GET    /.well-known/openid-configuration(.:format)                                                       doorkeeper/openid_connect/discovery#provider
#                                           GET    /.well-known/oauth-authorization-server(.:format)                                                 doorkeeper/openid_connect/discovery#provider
#                 oauth_discovery_webfinger GET    /.well-known/webfinger(.:format)                                                                  doorkeeper/openid_connect/discovery#webfinger
#                            oauth_userinfo GET    /oauth/userinfo(.:format)                                                                         oauth/userinfo#show
#                      oauth_oauth_metadata GET    /oauth/.well-known/oauth-authorization-server(.:format)                                           oauth/discovery#oauth_authorization_server
#                oauth_openid_configuration GET    /oauth/.well-known/openid-configuration(.:format)                                                 doorkeeper/openid_connect/discovery#provider
#                                           GET    /(*path)                                                                                          redirect(302)
#                                      root GET    /                                                                                                 home#index
#   accept_code_of_conduct_slack_onboarding POST   /slack/code-of-conduct(.:format)                                                                  slack_onboarding#accept_code_of_conduct
#                          slack_onboarding GET    /slack(.:format)                                                                                  slack_onboarding#show
#                                           POST   /slack(.:format)                                                                                  slack_onboarding#create
#                                           GET    /.well-known/*path                                                                                well_known#show
#                                           GET    /security.txt(.:format)                                                                           redirect(301, /.well-known/security.txt)
#                                    signup GET    /signup(.:format)                                                                                 users#new
#                                           POST   /signup(.:format)                                                                                 users#create
#                         username_conflict GET    /signup/username-conflict(.:format)                                                               users#username_conflict
#                                     login GET    /login(.:format)                                                                                  auth#new_session
#                            password_login GET    /login/pw(.:format)                                                                               auth#password_login
#                               oauth_login GET    /oauth/login(.:format)                                                                            auth#oauth_login
#                                           POST   /login(.:format)                                                                                  auth#login
#                           send_magic_link POST   /auth/magic_link(.:format)                                                                        auth#send_magic_link
#                          magic_link_login GET    /auth/magic_link/:token(.:format)                                                                 auth#magic_link_login
#                        confirm_magic_link POST   /auth/magic_link/:token(.:format)                                                                 auth#confirm_magic_link
#                      check_password_login POST   /auth/check_password_login(.:format)                                                              auth#check_password_login
#                                    logout DELETE /logout(.:format)                                                                                 auth#logout
#                                        me GET    /auth/me(.:format)                                                                                auth#me
#                                   profile GET    /profile(.:format)                                                                                users#show
#                              edit_profile GET    /profile/edit(.:format)                                                                           users#edit
#                          profile_sessions GET    /profile/sessions(.:format)                                                                       users#sessions
#                      destroy_all_sessions DELETE /profile/sessions(.:format)                                                                       users#destroy_all_sessions
#                                   session DELETE /profile/sessions/:id(.:format)                                                                   users#destroy_session
#                            update_profile PATCH  /profile(.:format)                                                                                users#update
#                        email_confirmation GET    /email_confirmation(.:format)                                                                     email_confirmations#show
#                             confirm_email GET    /confirm_email/:token(.:format)                                                                   email_confirmations#confirm
#                 resend_email_confirmation POST   /email_confirmation/resend(.:format)                                                              email_confirmations#resend
#                make_primary_email_address PATCH  /profile/emails/:id/make_primary(.:format)                                                        email_addresses#make_primary
#         resend_confirmation_email_address POST   /profile/emails/:id/resend_confirmation(.:format)                                                 email_addresses#resend_confirmation
#                           email_addresses POST   /profile/emails(.:format)                                                                         email_addresses#create
#                             email_address DELETE /profile/emails/:id(.:format)                                                                     email_addresses#destroy
#                     confirm_email_address GET    /emails/confirm/:token(.:format)                                                                  email_addresses#confirm
#                        user_profile_photo GET    /user/:p_id/pfp(.:format)                                                                         profile_photos#show
#                               user_avatar GET    /user/:p_id/avatar/:variant(.:format)                                                             profile_photos#avatar
#                        user_avatar_square GET    /user/:p_id/avatar/:variant/square(.:format)                                                      profile_photos#avatar_square
#                        user_avatar_circle GET    /user/:p_id/avatar/:variant/circle(.:format)                                                      profile_photos#avatar_circle
#                             user_initials GET    /user/:p_id/initials(/:variant)(.:format)                                                         profile_photos#initials {format: :svg}
#                      user_initials_circle GET    /user/:p_id/initials/:variant/circle(.:format)                                                    profile_photos#initials_circle {format: :svg}
#                        rails_health_check GET    /up(.:format)                                                                                     rails/health#show
#                               ok_computer        /ok                                                                                               OkComputer::Engine
#            stop_impersonating_admin_users DELETE /admin/users/stop_impersonating(.:format)                                                         admin/users#stop_impersonating
#                                admin_root GET    /admin(.:format)                                                                                  admin/dashboard#index
#                    impersonate_admin_user POST   /admin/users/:id/impersonate(.:format)                                                            admin/users#impersonate
#                      regen_pid_admin_user PATCH  /admin/users/:id/regen_pid(.:format)                                                              admin/users#regen_pid
#                invite_to_slack_admin_user POST   /admin/users/:id/invite_to_slack(.:format)                                                        admin/users#invite_to_slack
#                               admin_users GET    /admin/users(.:format)                                                                            admin/users#index
#                                           POST   /admin/users(.:format)                                                                            admin/users#create
#                            new_admin_user GET    /admin/users/new(.:format)                                                                        admin/users#new
#                           edit_admin_user GET    /admin/users/:id/edit(.:format)                                                                   admin/users#edit
#                                admin_user GET    /admin/users/:id(.:format)                                                                        admin/users#show
#                                           PATCH  /admin/users/:id(.:format)                                                                        admin/users#update
#                                           PUT    /admin/users/:id(.:format)                                                                        admin/users#update
#                                           DELETE /admin/users/:id(.:format)                                                                        admin/users#destroy
#                   admin_group_memberships POST   /admin/groups/:group_id/memberships(.:format)                                                     admin/group_memberships#create
#                    admin_group_membership DELETE /admin/groups/:group_id/memberships/:id(.:format)                                                 admin/group_memberships#destroy
#                              admin_groups GET    /admin/groups(.:format)                                                                           admin/groups#index
#                                           POST   /admin/groups(.:format)                                                                           admin/groups#create
#                           new_admin_group GET    /admin/groups/new(.:format)                                                                       admin/groups#new
#                          edit_admin_group GET    /admin/groups/:id/edit(.:format)                                                                  admin/groups#edit
#                               admin_group GET    /admin/groups/:id(.:format)                                                                       admin/groups#show
#                                           PATCH  /admin/groups/:id(.:format)                                                                       admin/groups#update
#                                           PUT    /admin/groups/:id(.:format)                                                                       admin/groups#update
#                                           DELETE /admin/groups/:id(.:format)                                                                       admin/groups#destroy
#                    activate_admin_service PATCH  /admin/services/:id/activate(.:format)                                                            admin/services#activate
#                  deactivate_admin_service PATCH  /admin/services/:id/deactivate(.:format)                                                          admin/services#deactivate
#                     suspend_admin_service PATCH  /admin/services/:id/suspend(.:format)                                                             admin/services#suspend
#                  revoke_admin_service_key PATCH  /admin/services/:service_id/keys/:id/revoke(.:format)                                             admin/service_keys#revoke
#               deprecate_admin_service_key PATCH  /admin/services/:service_id/keys/:id/deprecate(.:format)                                          admin/service_keys#deprecate
#                activate_admin_service_key PATCH  /admin/services/:service_id/keys/:id/activate(.:format)                                           admin/service_keys#activate
#                        admin_service_keys GET    /admin/services/:service_id/keys(.:format)                                                        admin/service_keys#index
#                                           POST   /admin/services/:service_id/keys(.:format)                                                        admin/service_keys#create
#                     new_admin_service_key GET    /admin/services/:service_id/keys/new(.:format)                                                    admin/service_keys#new
#                    edit_admin_service_key GET    /admin/services/:service_id/keys/:id/edit(.:format)                                               admin/service_keys#edit
#                         admin_service_key GET    /admin/services/:service_id/keys/:id(.:format)                                                    admin/service_keys#show
#                                           PATCH  /admin/services/:service_id/keys/:id(.:format)                                                    admin/service_keys#update
#                                           PUT    /admin/services/:service_id/keys/:id(.:format)                                                    admin/service_keys#update
#                                           DELETE /admin/services/:service_id/keys/:id(.:format)                                                    admin/service_keys#destroy
#            activate_admin_service_webhook PATCH  /admin/services/:service_id/webhooks/:id/activate(.:format)                                       admin/service_webhooks#activate
#          deactivate_admin_service_webhook PATCH  /admin/services/:service_id/webhooks/:id/deactivate(.:format)                                     admin/service_webhooks#deactivate
#                test_admin_service_webhook POST   /admin/services/:service_id/webhooks/:id/test(.:format)                                           admin/service_webhooks#test
#                    admin_service_webhooks GET    /admin/services/:service_id/webhooks(.:format)                                                    admin/service_webhooks#index
#                                           POST   /admin/services/:service_id/webhooks(.:format)                                                    admin/service_webhooks#create
#                 new_admin_service_webhook GET    /admin/services/:service_id/webhooks/new(.:format)                                                admin/service_webhooks#new
#                edit_admin_service_webhook GET    /admin/services/:service_id/webhooks/:id/edit(.:format)                                           admin/service_webhooks#edit
#                     admin_service_webhook GET    /admin/services/:service_id/webhooks/:id(.:format)                                                admin/service_webhooks#show
#                                           PATCH  /admin/services/:service_id/webhooks/:id(.:format)                                                admin/service_webhooks#update
#                                           PUT    /admin/services/:service_id/webhooks/:id(.:format)                                                admin/service_webhooks#update
#                                           DELETE /admin/services/:service_id/webhooks/:id(.:format)                                                admin/service_webhooks#destroy
#                            admin_services GET    /admin/services(.:format)                                                                         admin/services#index
#                                           POST   /admin/services(.:format)                                                                         admin/services#create
#                         new_admin_service GET    /admin/services/new(.:format)                                                                     admin/services#new
#                        edit_admin_service GET    /admin/services/:id/edit(.:format)                                                                admin/services#edit
#                             admin_service GET    /admin/services/:id(.:format)                                                                     admin/services#show
#                                           PATCH  /admin/services/:id(.:format)                                                                     admin/services#update
#                                           PUT    /admin/services/:id(.:format)                                                                     admin/services#update
#                                           DELETE /admin/services/:id(.:format)                                                                     admin/services#destroy
# regenerate_secret_admin_oauth_application PATCH  /admin/oauth_applications/:id/regenerate_secret(.:format)                                         admin/oauth_applications#regenerate_secret
#     access_policy_admin_oauth_application PATCH  /admin/oauth_applications/:id/access_policy(.:format)                                             admin/oauth_applications#access_policy
#   code_of_conduct_admin_oauth_application PATCH  /admin/oauth_applications/:id/code_of_conduct(.:format)                                           admin/oauth_applications#code_of_conduct
#     admin_oauth_application_access_grants POST   /admin/oauth_applications/:oauth_application_id/access_grants(.:format)                           admin/oauth_application_access_grants#create
#      admin_oauth_application_access_grant DELETE /admin/oauth_applications/:oauth_application_id/access_grants/:id(.:format)                       admin/oauth_application_access_grants#destroy
#  admin_oauth_application_role_assignments POST   /admin/oauth_applications/:oauth_application_id/roles/:role_id/assignments(.:format)              admin/oauth_application_role_assignments#create
#   admin_oauth_application_role_assignment DELETE /admin/oauth_applications/:oauth_application_id/roles/:role_id/assignments/:id(.:format)          admin/oauth_application_role_assignments#destroy
#             admin_oauth_application_roles POST   /admin/oauth_applications/:oauth_application_id/roles(.:format)                                   admin/oauth_application_roles#create
#              admin_oauth_application_role DELETE /admin/oauth_applications/:oauth_application_id/roles/:id(.:format)                               admin/oauth_application_roles#destroy
#                  admin_oauth_applications GET    /admin/oauth_applications(.:format)                                                               admin/oauth_applications#index
#                                           POST   /admin/oauth_applications(.:format)                                                               admin/oauth_applications#create
#               new_admin_oauth_application GET    /admin/oauth_applications/new(.:format)                                                           admin/oauth_applications#new
#              edit_admin_oauth_application GET    /admin/oauth_applications/:id/edit(.:format)                                                      admin/oauth_applications#edit
#                   admin_oauth_application GET    /admin/oauth_applications/:id(.:format)                                                           admin/oauth_applications#show
#                                           PATCH  /admin/oauth_applications/:id(.:format)                                                           admin/oauth_applications#update
#                                           PUT    /admin/oauth_applications/:id(.:format)                                                           admin/oauth_applications#update
#                                           DELETE /admin/oauth_applications/:id(.:format)                                                           admin/oauth_applications#destroy
#                admin_mission_control_jobs        /admin/jobs                                                                                       MissionControl::Jobs::Engine
#                          admin_audits1984        /admin/console                                                                                    Audits1984::Engine
#                                                  /admin/flipper                                                                                    Flipper::UI
#                              admin_blazer        /admin/blazer                                                                                     Blazer::Engine
#                                     admin GET    /admin(.:format)                                                                                  redirect(301, /login)
#                                           GET    /admin/*path(.:format)                                                                            redirect(301, /login)
#                         letter_opener_web        /letter_opener                                                                                    LetterOpenerWeb::Engine
#                             api_v1_health GET    /api/v1/health(.:format)                                                                          api/v1/health#index
#                    api_v1_directory_users GET    /api/v1/directory/users(.:format)                                                                 api/v1/directory/users#index
#                     api_v1_directory_user GET    /api/v1/directory/users/:sub(.:format)                                                            api/v1/directory/users#show
#                     webhooks_slack_events POST   /webhooks/slack/events(.:format)                                                                  webhooks/slack#events
#               webhooks_slack_interactions POST   /webhooks/slack/interactions(.:format)                                                            webhooks/slack#interactions
#          turbo_recede_historical_location GET    /recede_historical_location(.:format)                                                             turbo/native/navigation#recede
#          turbo_resume_historical_location GET    /resume_historical_location(.:format)                                                             turbo/native/navigation#resume
#         turbo_refresh_historical_location GET    /refresh_historical_location(.:format)                                                            turbo/native/navigation#refresh
#             rails_postmark_inbound_emails POST   /rails/action_mailbox/postmark/inbound_emails(.:format)                                           action_mailbox/ingresses/postmark/inbound_emails#create
#                rails_relay_inbound_emails POST   /rails/action_mailbox/relay/inbound_emails(.:format)                                              action_mailbox/ingresses/relay/inbound_emails#create
#             rails_sendgrid_inbound_emails POST   /rails/action_mailbox/sendgrid/inbound_emails(.:format)                                           action_mailbox/ingresses/sendgrid/inbound_emails#create
#       rails_mandrill_inbound_health_check GET    /rails/action_mailbox/mandrill/inbound_emails(.:format)                                           action_mailbox/ingresses/mandrill/inbound_emails#health_check
#             rails_mandrill_inbound_emails POST   /rails/action_mailbox/mandrill/inbound_emails(.:format)                                           action_mailbox/ingresses/mandrill/inbound_emails#create
#              rails_mailgun_inbound_emails POST   /rails/action_mailbox/mailgun/inbound_emails/mime(.:format)                                       action_mailbox/ingresses/mailgun/inbound_emails#create
#            rails_conductor_inbound_emails GET    /rails/conductor/action_mailbox/inbound_emails(.:format)                                          rails/conductor/action_mailbox/inbound_emails#index
#                                           POST   /rails/conductor/action_mailbox/inbound_emails(.:format)                                          rails/conductor/action_mailbox/inbound_emails#create
#         new_rails_conductor_inbound_email GET    /rails/conductor/action_mailbox/inbound_emails/new(.:format)                                      rails/conductor/action_mailbox/inbound_emails#new
#             rails_conductor_inbound_email GET    /rails/conductor/action_mailbox/inbound_emails/:id(.:format)                                      rails/conductor/action_mailbox/inbound_emails#show
#  new_rails_conductor_inbound_email_source GET    /rails/conductor/action_mailbox/inbound_emails/sources/new(.:format)                              rails/conductor/action_mailbox/inbound_emails/sources#new
#     rails_conductor_inbound_email_sources POST   /rails/conductor/action_mailbox/inbound_emails/sources(.:format)                                  rails/conductor/action_mailbox/inbound_emails/sources#create
#     rails_conductor_inbound_email_reroute POST   /rails/conductor/action_mailbox/:inbound_email_id/reroute(.:format)                               rails/conductor/action_mailbox/reroutes#create
#  rails_conductor_inbound_email_incinerate POST   /rails/conductor/action_mailbox/:inbound_email_id/incinerate(.:format)                            rails/conductor/action_mailbox/incinerates#create
#                        rails_service_blob GET    /rails/active_storage/blobs/redirect/:signed_id/*filename(.:format)                               active_storage/blobs/redirect#show
#                  rails_service_blob_proxy GET    /rails/active_storage/blobs/proxy/:signed_id/*filename(.:format)                                  active_storage/blobs/proxy#show
#                                           GET    /rails/active_storage/blobs/:signed_id/*filename(.:format)                                        active_storage/blobs/redirect#show
#                 rails_blob_representation GET    /rails/active_storage/representations/redirect/:signed_blob_id/:variation_key/*filename(.:format) active_storage/representations/redirect#show
#           rails_blob_representation_proxy GET    /rails/active_storage/representations/proxy/:signed_blob_id/:variation_key/*filename(.:format)    active_storage/representations/proxy#show
#                                           GET    /rails/active_storage/representations/:signed_blob_id/:variation_key/*filename(.:format)          active_storage/representations/redirect#show
#                        rails_disk_service GET    /rails/active_storage/disk/:encoded_key/*filename(.:format)                                       active_storage/disk#show
#                 update_rails_disk_service PUT    /rails/active_storage/disk/:encoded_token(.:format)                                               active_storage/disk#update
#                      rails_direct_uploads POST   /rails/active_storage/direct_uploads(.:format)                                                    active_storage/direct_uploads#create
#                          actual_db_schema        /rails                                                                                            ActualDbSchema::Engine
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
  get "/login/pw", to: "auth#password_login", as: :password_login
  get "/oauth/login", to: "auth#oauth_login", as: :oauth_login
  post "/login", to: "auth#login"
  post "/auth/magic_link", to: "auth#send_magic_link", as: :send_magic_link
  # GET only shows the confirmation screen; the POST is what actually signs in,
  # so link-scanning bots can't consume a link on the recipient's behalf.
  get "/auth/magic_link/:token", to: "auth#magic_link_login", as: :magic_link_login
  post "/auth/magic_link/:token", to: "auth#confirm_magic_link", as: :confirm_magic_link
  post "/auth/check_password_login", to: "auth#check_password_login", as: :check_password_login
  delete "/logout", to: "auth#logout", as: :logout
  get "/auth/me", to: "auth#me", as: :me

  # Profile management routes (requires authentication)
  get "/profile", to: "users#show", as: :profile
  get "/profile/edit", to: "users#edit", as: :edit_profile
  get "/profile/sessions", to: "users#sessions", as: :profile_sessions
  delete "/profile/sessions", to: "users#destroy_all_sessions", as: :destroy_all_sessions
  delete "/profile/sessions/:id", to: "users#destroy_session", as: :session
  patch "/profile", to: "users#update", as: :update_profile

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

  # Admin namespace with constraint
  constraints AdminConstraint.new do
    namespace :admin do
      # Admin dashboard is the root of the admin namespace
      root to: "dashboard#index"

      # Resources and sub-resources
      resources :users do
        member do
          post :impersonate
          patch :regen_pid
          post :invite_to_slack
          patch :code_of_conduct_exemption
        end
      end

      resources :groups do
        resources :memberships, controller: "group_memberships", only: [:create, :destroy]
      end

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
        end

        resources :access_grants, controller: "oauth_application_access_grants", only: [:create, :destroy]
        resources :roles, controller: "oauth_application_roles", only: [:create, :destroy] do
          resources :assignments, controller: "oauth_application_role_assignments", only: [:create, :destroy]
        end
      end

      # Mount engines under /admin path
      mount MissionControl::Jobs::Engine, at: "/jobs"
      mount Audits1984::Engine => "/console"
      mount Flipper::UI.app(Flipper), at: "/flipper"
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
        resources :users, only: [:index, :show], param: :sub
      end
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
