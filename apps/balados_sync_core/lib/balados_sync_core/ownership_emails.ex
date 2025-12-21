defmodule BaladosSyncCore.OwnershipEmails do
  @moduledoc """
  Email templates for podcast ownership verification.

  Uses Swoosh for email composition and delivery.
  In development, emails can be previewed at /dev/mailbox.
  """

  import Swoosh.Email

  @from_email "noreply@balados.sync"
  @from_name "Balados Sync"

  @doc """
  Builds the ownership verification email.

  ## Arguments
  - `to_email` - Recipient email address
  - `verification_code` - 6-digit verification code
  - `podcast_title` - Name of the podcast being verified
  - `feed_url` - URL of the podcast RSS feed
  """
  def ownership_verification_email(to_email, verification_code, podcast_title, feed_url) do
    new()
    |> to(to_email)
    |> from({@from_name, @from_email})
    |> subject("Podcast ownership verification - #{podcast_title}")
    |> html_body(verification_html(verification_code, podcast_title, feed_url))
    |> text_body(verification_text(verification_code, podcast_title, feed_url))
  end

  defp verification_html(code, title, feed_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; }
        .code { font-size: 32px; font-weight: bold; letter-spacing: 8px; background: #f4f4f5; padding: 20px 30px; border-radius: 8px; text-align: center; margin: 30px 0; font-family: monospace; }
        .info { background: #fafafa; padding: 15px; border-radius: 8px; margin: 20px 0; }
        .info dt { font-weight: 600; color: #666; }
        .info dd { margin: 5px 0 15px 0; word-break: break-all; }
        .warning { background: #fef3c7; border-left: 4px solid #f59e0b; padding: 15px; margin: 20px 0; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; color: #666; font-size: 14px; }
      </style>
    </head>
    <body>
      <h1>Podcast Ownership Verification</h1>

      <p>Someone requested to verify ownership of the following podcast on Balados Sync:</p>

      <dl class="info">
        <dt>Podcast</dt>
        <dd>#{escape_html(title)}</dd>
        <dt>Feed URL</dt>
        <dd>#{escape_html(feed_url)}</dd>
      </dl>

      <p>To complete verification, enter this code on the verification page:</p>

      <div class="code">#{code}</div>

      <div class="warning">
        <strong>Important:</strong>
        <ul>
          <li>This code expires in 30 minutes</li>
          <li>If you did not request this, you can safely ignore this email</li>
          <li>Never share this code with anyone</li>
        </ul>
      </div>

      <div class="footer">
        <p>This email was sent because this address is listed in the podcast's RSS feed.</p>
        <p>Balados Sync - Open podcast synchronization platform</p>
      </div>
    </body>
    </html>
    """
  end

  defp verification_text(code, title, feed_url) do
    """
    PODCAST OWNERSHIP VERIFICATION
    ==============================

    Someone requested to verify ownership of the following podcast on Balados Sync:

    Podcast: #{title}
    Feed URL: #{feed_url}

    To complete verification, enter this code on the verification page:

    #{code}

    IMPORTANT:
    - This code expires in 30 minutes
    - If you did not request this, you can safely ignore this email
    - Never share this code with anyone

    ---
    This email was sent because this address is listed in the podcast's RSS feed.
    Balados Sync - Open podcast synchronization platform
    """
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  @doc """
  Delivers the verification email using the configured mailer.

  Returns {:ok, email} on success or {:error, reason} on failure.
  """
  def deliver_verification_email(to_email, verification_code, podcast_title, feed_url) do
    email = ownership_verification_email(to_email, verification_code, podcast_title, feed_url)

    case BaladosSyncCore.Mailer.deliver(email) do
      {:ok, _metadata} ->
        {:ok, email}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
