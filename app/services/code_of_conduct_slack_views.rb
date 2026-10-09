# frozen_string_literal: true

# Block Kit payloads for the code-of-conduct DM and form (see
# SlackService#post_code_of_conduct and #open_code_of_conduct_form). Plain
# hashes, as Slack's Block Kit reference documents them:
# https://docs.slack.dev/reference/block-kit/blocks
module CodeOfConductSlackViews
  # callback_id of the form. The interactions webhook routes on it.
  FORM_CALLBACK = "coc_form"

  # block_id of each field on the form. Each input's action_id is "value".
  # A pair of fields shares one hint, under its second field. The /slack page
  # uses the same list.
  NAME_FIELDS = {
    first_name: { label: "Preferred first name", hint_for: :last_name },
    last_name: { label: "Preferred last name", hint: :preferred_hint },
    legal_first_name: { label: "Legal first name", optional: true, hint_for: :legal_last_name },
    legal_last_name: { label: "Legal last name", hint: :legal_hint, optional: true },
    slack_name: { label: "Slack nickname", hint: :slack_name_hint, optional: true, max_length: 80 }
  }.freeze

  module_function

  # The DM. button is { text:, action_id:, value: }.
  def request(title:, paragraphs:, action_text:, button:, coc_url:, web_url:)
    blocks = [header(title), *paragraphs.map { |paragraph| section(paragraph) }]
    if coc_url.present?
      blocks << section(":scroll: *Code of Conduct*\nIt explains how we treat each other in Patchwork Labs.",
                        accessory: link_button("Read it", coc_url))
    end
    blocks << { type: "divider" }
    blocks << section(action_text)
    blocks << {
      type: "actions",
      elements: [{ type: "button", style: "primary", text: plain(button[:text]), action_id: button[:action_id], value: button[:value] }]
    }
    blocks << context("You can also accept on Weave: <#{web_url}|#{web_url.delete_prefix('https://')}>")
    { blocks: blocks }
  end

  # The form. ask_name adds the name fields.
  def form(ask_name:, coc_url:, private_metadata:)
    intro = t(:intro)
    blocks = [coc_url.present? ? section(intro, accessory: link_button("Read it", coc_url)) : section(intro)]

    if ask_name
      blocks << { type: "divider" }
      blocks << section(t(:name_why))
      NAME_FIELDS.each { |block_id, field| blocks << text_input(block_id, **field) }
    end

    blocks << { type: "divider" }
    blocks << {
      type: "input",
      block_id: "accept",
      label: plain("Code of Conduct"),
      element: {
        type: "checkboxes",
        action_id: "value",
        options: [{ text: plain(t(:accept_label)), value: "accept" }]
      }
    }
    blocks << context(":lock: *#{t(:data_use_title)}*\n#{t(:data_use)}")

    {
      type: "modal",
      callback_id: FORM_CALLBACK,
      private_metadata: private_metadata,
      title: plain("Code of Conduct"),
      submit: plain("I accept"),
      close: plain("Not now"),
      blocks: blocks
    }
  end

  def t(key) = I18n.t("code_of_conduct_form.#{key}")
  def plain(text) = { type: "plain_text", text: text }
  def header(text) = { type: "header", text: plain(text) }
  def context(text) = { type: "context", elements: [{ type: "mrkdwn", text: text }] }

  def section(text, accessory: nil)
    { type: "section", text: { type: "mrkdwn", text: text }, accessory: accessory }.compact
  end

  # A URL button still sends a click to the interactions webhook, which
  # ignores the action_id.
  def link_button(text, url) = { type: "button", text: plain(text), action_id: "read_coc", url: url }

  def text_input(block_id, label:, hint: nil, optional: false, max_length: 100, hint_for: nil)
    {
      type: "input",
      block_id: block_id.to_s,
      optional: optional,
      label: plain(label),
      hint: (plain(t(hint)) if hint),
      element: { type: "plain_text_input", action_id: "value", max_length: max_length }
    }.compact
  end
end
