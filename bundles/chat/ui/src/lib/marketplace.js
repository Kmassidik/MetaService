import google from '../assets/plugins/google.svg'
import github from '../assets/plugins/github.svg'
import x from '../assets/plugins/x.svg'
import facebook from '../assets/plugins/facebook.svg'
import notion from '../assets/plugins/notion.svg'
import slack from '../assets/plugins/slack.svg'
import discord from '../assets/plugins/discord.svg'
import instagram from '../assets/plugins/instagram.svg'
import linkedin from '../assets/plugins/linkedin.svg'
import telegram from '../assets/plugins/telegram.svg'
import whatsapp from '../assets/plugins/whatsapp.svg'
import reddit from '../assets/plugins/reddit.svg'
import outlook from '../assets/plugins/outlook.svg'
import microsoftteams from '../assets/plugins/microsoftteams.svg'
import linear from '../assets/plugins/linear.svg'
import jira from '../assets/plugins/jira.svg'
import confluence from '../assets/plugins/confluence.svg'
import airtable from '../assets/plugins/airtable.svg'
import dropbox from '../assets/plugins/dropbox.svg'
import onedrive from '../assets/plugins/onedrive.svg'
import figma from '../assets/plugins/figma.svg'
import zoom from '../assets/plugins/zoom.svg'
import hubspot from '../assets/plugins/hubspot.svg'
import salesforce from '../assets/plugins/salesforce.svg'
import intercom from '../assets/plugins/intercom.svg'
import zendesk from '../assets/plugins/zendesk.svg'
import shopify from '../assets/plugins/shopify.svg'
import stripe from '../assets/plugins/stripe.svg'

export const pluginCategories = [
  { id: 'social', label: 'Social & messaging' },
  { id: 'work', label: 'Work & productivity' },
  { id: 'business', label: 'Business' },
]

const how = name => `Tap Connect. Your computer opens ${name}. Sign in there (password and 2FA yourself). Ruvio notices the sign-in on its own, or tap I’m signed in. Every bot uses this login.`

/**
 * Apps your bots use through your computer’s browser (one login per account, shared by every bot).
 * Connect = open the computer on the login page; you sign in; the session stays in that browser.
 *
 * `verified`: the guest login check (cookie probe lib/maas-desktop-probe.py, or the live page check
 * lib/apptools/login-check.mjs for WhatsApp) was checked against a real sign-in on a real computer
 * (WhatsApp: tests/e2e/apptools/whatsapp_self.py). Only verified apps can be connected; an unverified
 * one shows greyed out as "Soon" until that check passes ("if we can't test it, don't ship it").
 * Flip the flag only after that real check.
 */
export const platformPlugins = [
  { id: 'google', verified: true, name: 'Google', category: 'work', blurb: 'Gmail, Drive, Calendar and YouTube: one sign-in covers them all.', logo: google, loginUrl: 'https://accounts.google.com/', how: 'Tap Connect. Your computer opens Google sign-in. Sign in there (password and 2FA yourself). One Google sign-in in your computer’s Chrome covers Gmail, Drive, Calendar and YouTube, and every bot uses it.' },
  { id: 'x', verified: true, name: 'X', category: 'social', blurb: 'Post and read on X.', logo: x, loginUrl: 'https://x.com/i/flow/login', how: 'Tap Connect. Your computer opens X. If the screen stays blank, X blocked the browser (HTTP 403) — that is X, not a dead computer. Try google.com in the address bar to confirm. A different X connect path is needed when that happens.' },
  { id: 'facebook', verified: false, name: 'Facebook', category: 'social', blurb: 'Pages and posts.', logo: facebook, loginUrl: 'https://www.facebook.com/login', how: how('Facebook') },
  { id: 'instagram', verified: false, name: 'Instagram', category: 'social', blurb: 'Posts and DMs.', logo: instagram, loginUrl: 'https://www.instagram.com/accounts/login/', how: how('Instagram') },
  { id: 'linkedin', verified: false, name: 'LinkedIn', category: 'social', blurb: 'Posts and company pages.', logo: linkedin, loginUrl: 'https://www.linkedin.com/login', how: how('LinkedIn') },
  { id: 'discord', verified: false, name: 'Discord', category: 'social', blurb: 'Servers and channels.', logo: discord, loginUrl: 'https://discord.com/login', how: how('Discord') },
  { id: 'telegram', verified: false, name: 'Telegram', category: 'social', blurb: 'Chats in Telegram Web.', logo: telegram, loginUrl: 'https://web.telegram.org/', how: how('Telegram') },
  { id: 'whatsapp', verified: true, name: 'WhatsApp', category: 'social', blurb: 'Message people as you, with your approval first.', logo: whatsapp, loginUrl: 'https://web.whatsapp.com/', how: 'Tap Connect. Your computer opens WhatsApp Web with a QR code. On your phone open WhatsApp › Settings › Linked devices › Link a device and scan it. Ruvio notices once your chats show, or tap I’m signed in. Bots message people only after you tap Send.' },
  { id: 'reddit', verified: false, name: 'Reddit', category: 'social', blurb: 'Posts and subreddits.', logo: reddit, loginUrl: 'https://www.reddit.com/login/', how: how('Reddit') },

  { id: 'outlook', verified: false, name: 'Outlook', category: 'work', blurb: 'Microsoft mail and calendar.', logo: outlook, loginUrl: 'https://outlook.live.com/mail/', how: how('Outlook') },
  { id: 'github', verified: false, name: 'GitHub', category: 'work', blurb: 'Issues, PRs, and repos.', logo: github, loginUrl: 'https://github.com/login', how: how('GitHub') },
  { id: 'slack', verified: false, name: 'Slack', category: 'work', blurb: 'Channels and DMs.', logo: slack, loginUrl: 'https://slack.com/signin', how: how('Slack') },
  { id: 'microsoft-teams', verified: false, name: 'Microsoft Teams', category: 'work', blurb: 'Teams chat and channels.', logo: microsoftteams, loginUrl: 'https://teams.microsoft.com/', how: how('Microsoft Teams') },
  { id: 'onedrive', verified: false, name: 'OneDrive', category: 'work', blurb: 'Files in OneDrive.', logo: onedrive, loginUrl: 'https://onedrive.live.com/', how: how('OneDrive') },
  { id: 'dropbox', verified: false, name: 'Dropbox', category: 'work', blurb: 'Files in Dropbox.', logo: dropbox, loginUrl: 'https://www.dropbox.com/login', how: how('Dropbox') },
  { id: 'notion', verified: false, name: 'Notion', category: 'work', blurb: 'Pages and notes.', logo: notion, loginUrl: 'https://www.notion.so/login', how: how('Notion') },
  { id: 'linear', verified: false, name: 'Linear', category: 'work', blurb: 'Issues and projects.', logo: linear, loginUrl: 'https://linear.app/login', how: how('Linear') },
  { id: 'jira', verified: false, name: 'Jira', category: 'work', blurb: 'Tickets and boards.', logo: jira, loginUrl: 'https://id.atlassian.com/login', how: how('Jira') },
  { id: 'confluence', verified: false, name: 'Confluence', category: 'work', blurb: 'Docs and spaces.', logo: confluence, loginUrl: 'https://id.atlassian.com/login', how: how('Confluence') },
  { id: 'airtable', verified: false, name: 'Airtable', category: 'work', blurb: 'Bases and records.', logo: airtable, loginUrl: 'https://airtable.com/login', how: how('Airtable') },
  { id: 'figma', verified: false, name: 'Figma', category: 'work', blurb: 'Files and comments.', logo: figma, loginUrl: 'https://www.figma.com/login', how: how('Figma') },
  { id: 'zoom', verified: false, name: 'Zoom', category: 'work', blurb: 'Meetings and recordings.', logo: zoom, loginUrl: 'https://zoom.us/signin', how: how('Zoom') },

  { id: 'hubspot', verified: false, name: 'HubSpot', category: 'business', blurb: 'CRM and pipelines.', logo: hubspot, loginUrl: 'https://app.hubspot.com/login', how: how('HubSpot') },
  { id: 'salesforce', verified: false, name: 'Salesforce', category: 'business', blurb: 'CRM records and leads.', logo: salesforce, loginUrl: 'https://login.salesforce.com/', how: how('Salesforce') },
  { id: 'intercom', verified: false, name: 'Intercom', category: 'business', blurb: 'Inbox and customers.', logo: intercom, loginUrl: 'https://app.intercom.com/admins/sign_in', how: how('Intercom') },
  { id: 'zendesk', verified: false, name: 'Zendesk', category: 'business', blurb: 'Support tickets.', logo: zendesk, loginUrl: 'https://www.zendesk.com/login/', how: how('Zendesk') },
  { id: 'shopify', verified: false, name: 'Shopify', category: 'business', blurb: 'Store and orders.', logo: shopify, loginUrl: 'https://accounts.shopify.com/store-login', how: how('Shopify') },
  { id: 'stripe', verified: false, name: 'Stripe', category: 'business', blurb: 'Payments and customers.', logo: stripe, loginUrl: 'https://dashboard.stripe.com/login', how: how('Stripe') },
]

/** What Connect apps shows for an app: connectable now, or greyed out as coming soon. */
export const PluginStatus = Object.freeze({
  AVAILABLE: 'available',
  SOON: 'soon',
})

const STATUS_ORDER = [PluginStatus.AVAILABLE, PluginStatus.SOON]

/** The one place the `verified` flag turns into what the catalog shows. */
export function pluginStatus(plugin) {
  return plugin.verified ? PluginStatus.AVAILABLE : PluginStatus.SOON
}

export const isAvailable = plugin => pluginStatus(plugin) === PluginStatus.AVAILABLE

/** Working apps first, then Soon ones; the catalog order is kept within each (a stable sort). */
export function sortByStatus(plugins) {
  const rank = plugin => STATUS_ORDER.indexOf(pluginStatus(plugin))
  return [...plugins].sort((a, b) => rank(a) - rank(b))
}

/** Every app Connect apps lists, working ones first. */
export const catalogPlugins = sortByStatus(platformPlugins)

/** A catalog app by id, working or Soon; null for an id this build does not know. */
export function pluginById(id) {
  return platformPlugins.find(plugin => plugin.id === id) || null
}

/** True when the app can be connected now (known to this build and not Soon). */
export function isConnectable(id) {
  const plugin = pluginById(id)
  return Boolean(plugin) && isAvailable(plugin)
}
