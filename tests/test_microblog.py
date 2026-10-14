#!/usr/bin/env python3
# Copyright (c) 2026 https://uyasoo.com
# SPDX-License-Identifier: MIT

"""Exercise the uYasoo microblog against a real OpenASP binary and Redis."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlencode


SITE = Path(__file__).resolve().parent.parent
ROOT = SITE
OPENASP = ROOT / "build/openasp"
REDIS_DB = "9"
STATE_DIR = ""
OPTIMIZE = os.environ.get("OPENASP_OPTIMIZE", "on")


def redis(*args: str) -> str:
    result = subprocess.run(
        ["redis-cli", "-n", REDIS_DB, *args],
        check=True,
        capture_output=True,
        text=True,
        timeout=10,
    )
    return result.stdout.strip()


def remember_tokens_for(user_id: str) -> list[str]:
    keys = redis("KEYS", "openasp:microblog:remember:*").splitlines()
    return [key for key in keys if redis("GET", key) == user_id]


def email_key(email: str) -> str:
    digest = hashlib.sha256(email.strip().lower().encode()).hexdigest()
    return f"openasp:microblog:email:{digest}"


def request(
    session: str,
    *,
    page: str = "default.asp",
    query: str = "",
    form: dict[str, str] | None = None,
) -> tuple[str, str]:
    command = [
        str(OPENASP),
        "render",
        "--file",
        str(SITE / page),
        "--root",
        str(SITE),
        "--session",
        session,
        f"--optimize={OPTIMIZE}",
        "--log-file",
        "off",
    ]
    if query:
        command.extend(["--query", query])
    if form is not None:
        command.extend(["--method", "POST", "--body", urlencode(form)])
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        env={**os.environ, "EGRET_ASP_STATE_DIR": STATE_DIR},
        text=True,
        timeout=30,
    )
    body, separator, metadata = result.stdout.partition("----")
    assert separator, result.stdout
    assert "error_number=0" in metadata, metadata
    if any(status in metadata for status in ("status=401", "status=403", "status=404")):
        assert result.returncode in (0, 1), (result.stdout, result.stderr)
    else:
        assert result.returncode == 0, (result.stdout, result.stderr)
    return body, metadata


def request_binary(
    session: str,
    *,
    page: str,
    query: str = "",
) -> tuple[bytes, str]:
    command = [
        str(OPENASP),
        "render",
        "--file",
        str(SITE / page),
        "--root",
        str(SITE),
        "--session",
        session,
        f"--optimize={OPTIMIZE}",
        "--log-file",
        "off",
    ]
    if query:
        command.extend(["--query", query])
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        env={**os.environ, "EGRET_ASP_STATE_DIR": STATE_DIR},
        timeout=30,
    )
    body, separator, metadata_bytes = result.stdout.rpartition(b"\n----\n")
    assert separator, result.stdout[-1000:]
    if body.endswith(b"\n"):
        body = body[:-1]
    metadata = metadata_bytes.decode()
    assert "error_number=0" in metadata, metadata
    if any(status in metadata for status in ("status=401", "status=403", "status=404")):
        assert result.returncode in (0, 1), (metadata, result.stderr.decode(errors="replace"))
    else:
        assert result.returncode == 0, (metadata, result.stderr.decode(errors="replace"))
    return body, metadata


def csrf(session: str, query: str = "view=auth") -> str:
    body, metadata = request(session, query=query)
    assert "status=200" in metadata, metadata
    match = re.search(r'name="csrf" value="([a-f0-9]+)"', body)
    assert match is not None, body
    return match.group(1)


def captcha_code(session: str) -> str:
    body, metadata = request(session, page="captcha.asp")
    assert "status=200" in metadata, metadata
    assert "content_type=image/svg+xml" in metadata, metadata
    assert 'width="150" height="40"' in body
    characters = re.findall(r'class="captcha-character"[^>]*>([A-F0-9])</text>', body)
    assert len(characters) == 6, body
    assert body.count("<line ") >= 7 and body.count("<circle ") >= 40
    return "".join(characters)


def post(session: str, action: str, fields: dict[str, str]) -> tuple[str, str]:
    token_query = "view=auth" if action in ("register", "login") else ""
    payload = {"action": action, "csrf": csrf(session, query=token_query)}
    if action == "register":
        payload["captcha"] = captcha_code(session)
    payload.update(fields)
    return request(session, form=payload)


def post_ajax(session: str, action: str, fields: dict[str, str]) -> tuple[dict[str, object], str]:
    token_query = "view=auth" if action in ("register", "login") else ""
    payload = {"action": action, "csrf": csrf(session, query=token_query)}
    if action == "register":
        payload["captcha"] = captcha_code(session)
    payload.update(fields)
    body, metadata = request(session, query="_ajax=1", form=payload)
    return json.loads(body), metadata


def assert_redirect(metadata: str) -> None:
    assert "status=302" in metadata, metadata


def main() -> None:
    global STATE_DIR
    assert OPENASP.is_file(), f"OpenASP binary is missing: {OPENASP}"
    assert redis("PING") == "PONG"
    assert redis("FLUSHDB") == "OK"

    with tempfile.TemporaryDirectory(prefix="openasp-microblog-test-") as state_dir:
        STATE_DIR = state_dir
        run_scenario()


def run_scenario() -> None:
    alice_session = "microblog-test-alice"
    bob_session = "microblog-test-bob"
    app_js = (SITE / "assets/app.js").read_text()
    assert 'form.getAttribute("action")' in app_js
    assert 'endpoint.searchParams.set("_ajax", "1")' in app_js
    assert "new URLSearchParams()" in app_js
    assert "const prependPublishedPost = async (postId)" in app_js
    assert 'submitButton.textContent = "Posting..."' in app_js
    assert 'showAjaxNotice("Your post is live. Refresh the feed to see it.")' in app_js
    assert "}, 2000);" in app_js
    assert "const syncEnglishValidationMessage = (control)" in app_js
    assert "document.querySelectorAll(formControlSelector).forEach(syncEnglishValidationMessage)" in app_js
    assert "form.noValidate = true" in app_js
    assert "const validateForm = (form)" in app_js
    assert "form.reportValidity()" not in app_js
    assert app_js.index('form.dispatchEvent(new CustomEvent("ajax:success"))') < app_js.index(
        "prependPublishedPost(payload.post_id)"
    )
    assert "feed-page.asp" in app_js
    assert "window.location.reload()" not in app_js
    app_css = (SITE / "assets/app.css").read_text()
    assert ".post-card-enter" in app_css
    assert "@media (prefers-reduced-motion: reduce)" in app_css
    assert "grid-template-columns: minmax(0, 1fr) auto;" in app_css
    assert ".comment-form .mention-input-wrap" in app_css
    assert "CacheUploadedImage(storedPath, avatarData)" in (SITE / "upload-avatar.asp").read_text()
    assert "CacheUploadedImage(storedPath, imageData)" in (SITE / "publish-post.asp").read_text()

    auth_page, metadata = request(alice_session, query="view=auth")
    assert "status=200" in metadata
    assert 'class="auth-grid"' in auth_page
    assert '<header class="topbar">' not in auth_page
    assert 'aria-label="Account"' not in auth_page
    assert 'class="auth-home-link" href="/"' in auth_page
    assert 'class="ui-icon ui-icon-arrow-left"' in auth_page
    assert "Back to home" in auth_page
    assert auth_page.count('class="field-label"') == 7
    assert auth_page.count('class="required-marker" aria-hidden="true">*</span>') == 7

    rejected_code = captcha_code(alice_session)
    _, metadata = request(
        alice_session,
        form={
            "action": "register",
            "csrf": csrf(alice_session),
            "captcha": "000000" if rejected_code != "000000" else "FFFFFF",
            "display_name": "Rejected",
            "username": "rejected",
            "email": "rejected@example.com",
            "password": "not-created",
        },
    )
    assert_redirect(metadata)
    assert redis("EXISTS", "openasp:microblog:username:rejected") == "0"

    _, metadata = post(
        "microblog-test-invalid-email",
        "register",
        {
            "display_name": "Invalid Email",
            "username": "invalid_email",
            "email": "not-an-email",
            "password": "not-created",
        },
    )
    assert_redirect(metadata)
    assert redis("EXISTS", "openasp:microblog:username:invalid_email") == "0"

    _, metadata = post(
        alice_session,
        "register",
        {
            "display_name": "Alice Chen",
            "username": "alice",
            "email": "Alice@Example.com",
            "password": "correct-horse",
        },
    )
    assert_redirect(metadata)

    _, metadata = post(
        bob_session,
        "register",
        {
            "display_name": "Bob Lin",
            "username": "bob",
            "email": "bob@example.com",
            "password": "battery-staple",
        },
    )
    assert_redirect(metadata)

    assert redis("GET", "openasp:microblog:username:alice") == "1"
    assert redis("GET", "openasp:microblog:username:bob") == "2"
    assert redis("HGET", "openasp:microblog:user:1", "email") == "alice@example.com"
    assert redis("HGET", "openasp:microblog:user:2", "email") == "bob@example.com"
    assert redis("GET", email_key("ALICE@example.com")) == "1"
    assert redis("GET", email_key("bob@example.com")) == "2"
    assert redis("HGET", "openasp:microblog:user:1", "avatar") == "assets/avatars/avatar-01.jpg"
    assert redis("HGET", "openasp:microblog:user:2", "avatar") == "assets/avatars/avatar-02.jpg"
    alice_tokens = remember_tokens_for("1")
    bob_tokens = remember_tokens_for("2")
    assert len(alice_tokens) == 1 and len(bob_tokens) == 1
    assert 2591900 <= int(redis("TTL", alice_tokens[0])) <= 2592000
    assert 2591900 <= int(redis("TTL", bob_tokens[0])) <= 2592000

    _, metadata = post(
        "microblog-test-duplicate-email",
        "register",
        {
            "display_name": "Duplicate Email",
            "username": "duplicate_email",
            "email": "ALICE@example.com",
            "password": "not-created",
        },
    )
    assert_redirect(metadata)
    assert redis("EXISTS", "openasp:microblog:username:duplicate_email") == "0"
    assert redis("GET", email_key("alice@example.com")) == "1"
    assert redis("EXISTS", "openasp:microblog:user:3") == "0"

    suggestions, metadata = request(
        alice_session,
        page="mention-users.asp",
        query="q=bo",
    )
    assert "status=200" in metadata
    suggestion_payload = json.loads(suggestions)
    assert suggestion_payload["users"] == [
        {
            "id": "2",
            "username": "bob",
            "display_name": "Bob Lin",
            "avatar": "assets/avatars/avatar-02.jpg",
        },
    ]

    body, metadata = request(alice_session)
    assert "status=200" in metadata
    assert "Alice Chen" in body and "What is happening?" in body
    assert 'rel="icon" type="image/svg+xml" href="assets/favicon.svg?' in body
    assert 'action="publish-post.asp"' in body
    assert 'enctype="multipart/form-data"' in body
    assert 'data-composer-toggle="emoji"' in body
    assert 'name="image"' in body
    assert 'name="link_url"' in body
    assert 'class="ui-icon ui-icon-smile"' in body
    assert 'class="ui-icon ui-icon-image"' in body
    assert 'class="ui-icon ui-icon-link"' in body
    assert "<title>uYasoo</title>" in body
    assert 'placeholder="Search uYasoo"' in body
    assert '<span class="brand-mark">Y</span>' in body
    assert "Powered By" in body and "OpenASP.dev" in body
    assert 'href="/?view=topics">Topics</a>' in body
    assert 'id="feed-update-bar"' in body
    assert 'data-after="0"' in body
    assert 'id="feed-list"' in body

    updates, metadata = request(
        "microblog-test-guest",
        page="feed-updates.asp",
        query="after=0",
    )
    assert "status=401" in metadata
    assert json.loads(updates) == {"count": 0, "latest_id": 0}

    topics, metadata = request(alice_session, query="view=topics")
    assert "status=200" in metadata
    assert "No topics yet" in topics

    invalid_body, invalid_metadata = request(
        alice_session,
        form={"action": "publish", "csrf": "invalid", "body": "blocked"},
    )
    assert "status=403" in invalid_metadata
    assert "Invalid or expired form token." in invalid_body
    assert redis("LLEN", "openasp:microblog:posts:global") == "0"

    invalid_ajax_body, invalid_ajax_metadata = request(
        alice_session,
        query="_ajax=1",
        form={"action": "publish", "csrf": "invalid", "body": "blocked"},
    )
    assert "status=403" in invalid_ajax_metadata
    assert json.loads(invalid_ajax_body) == {
        "ok": False,
        "message": "Invalid or expired form token.",
        "redirect": "/",
    }

    _, metadata = request(
        alice_session,
        page="publish-post.asp",
        form={"csrf": csrf(alice_session, query=""), "body": "not multipart"},
    )
    assert_redirect(metadata)
    assert redis("LLEN", "openasp:microblog:posts:global") == "0"

    _, metadata = post(
        bob_session,
        "publish",
        {"body": "Shipping #OpenASP# with #Redis# and #OpenASP#."},
    )
    assert_redirect(metadata)
    assert redis("HGET", "openasp:microblog:post:1", "author_id") == "2"
    assert redis("LLEN", "openasp:microblog:topic:openasp:posts") == "1"
    assert redis("LLEN", "openasp:microblog:topic:redis:posts") == "1"
    assert redis("ZSCORE", "openasp:microblog:topics:counts", "openasp") == "1"

    alice_home, metadata = request(alice_session)
    assert "status=200" in metadata
    assert "Shipping" not in alice_home
    updates, metadata = request(
        alice_session,
        page="feed-updates.asp",
        query="after=0",
    )
    assert "status=200" in metadata
    assert json.loads(updates) == {"count": 0, "latest_id": 1}, updates

    ajax_payload, metadata = post_ajax(alice_session, "follow", {"target_id": "2"})
    assert "status=200" in metadata, metadata
    assert ajax_payload["ok"] is True
    assert ajax_payload["target_id"] == "2"
    assert ajax_payload["following"] == "True"
    assert ajax_payload["follower_count"] == "1"
    assert ajax_payload["message"] == "You are now following Bob Lin."
    assert redis("SISMEMBER", "openasp:microblog:following:1", "2") == "1"
    assert redis("SISMEMBER", "openasp:microblog:followers:2", "1") == "1"

    alice_home, metadata = request(alice_session)
    assert "status=200" in metadata
    assert "Shipping" in alice_home
    assert 'href="/?view=topic&name=openasp">#OpenASP#</a>' in alice_home
    assert 'data-after="1"' in alice_home

    updates, metadata = request(
        alice_session,
        page="feed-updates.asp",
        query="after=1",
    )
    assert "status=200" in metadata
    assert json.loads(updates) == {"count": 0, "latest_id": 1}, updates

    _, metadata = post(
        bob_session,
        "publish",
        {"body": "A fresh update for followers."},
    )
    assert_redirect(metadata)
    updates, metadata = request(
        alice_session,
        page="feed-updates.asp",
        query="after=1",
    )
    assert "status=200" in metadata
    assert json.loads(updates) == {"count": 1, "latest_id": 2}, updates

    feed_fragment, metadata = request(
        alice_session,
        page="feed-fragment.asp",
        query="after=1",
    )
    assert "status=200" in metadata, metadata
    assert 'data-post-id="2"' in feed_fragment
    assert "A fresh update for followers." in feed_fragment

    topics, metadata = request(alice_session, query="view=topics")
    assert "status=200" in metadata
    assert "#</span><span><strong>OpenASP</strong><small>1 post" in topics
    assert "#</span><span><strong>Redis</strong><small>1 post" in topics
    topic_feed, metadata = request(alice_session, query="view=topic&name=openasp")
    assert "status=200" in metadata
    assert "Shipping" in topic_feed and "#OpenASP#" in topic_feed

    ajax_payload, metadata = post_ajax(alice_session, "like", {"post_id": "1"})
    assert "status=200" in metadata, metadata
    assert ajax_payload["post_id"] == "1"
    ajax_payload, metadata = post_ajax(
        alice_session,
        "comment",
        {"post_id": "1", "body": "Strong launch. Congratulations!"},
    )
    assert "status=200" in metadata, metadata
    assert ajax_payload["message"] == "Comment added."

    fragment, metadata = request(
        alice_session,
        page="post-fragment.asp",
        query="id=1&comments=1",
    )
    assert "status=200" in metadata, metadata
    assert 'data-post-id="1"' in fragment
    assert "Strong launch. Congratulations!" in fragment

    conversation, metadata = request(alice_session, query="view=post&id=1")
    assert "status=200" in metadata
    assert 'class="post-action post-like-action active"' in conversation
    assert 'aria-label="Unlike post, 1 like"' in conversation
    assert 'class="ui-icon ui-icon-heart"' in conversation
    assert 'aria-label="View 1 comment"' in conversation
    assert 'class="ui-icon ui-icon-message"' in conversation
    assert "Strong launch. Congratulations!" in conversation
    assert redis("SCARD", "openasp:microblog:post:1:likes") == "1"

    followers, metadata = request(bob_session, query="view=followers&id=2")
    assert "status=200" in metadata
    assert "Alice Chen" in followers

    search, metadata = request(bob_session, query="view=search&q=alice")
    assert "status=200" in metadata
    assert "@alice" in search

    _, metadata = post(
        alice_session,
        "edit_profile",
        {"display_name": "Alice C.", "bio": "Building portable web software."},
    )
    assert_redirect(metadata)
    profile, metadata = request(bob_session, query="view=profile&id=1")
    assert "status=200" in metadata
    assert "Alice C." in profile
    assert "Building portable web software." in profile
    assert 'src="assets/avatars/avatar-01.jpg"' in profile

    _, metadata = post(
        alice_session,
        "select_avatar",
        {"avatar": "assets/avatars/avatar-08.jpg"},
    )
    assert_redirect(metadata)
    assert redis("HGET", "openasp:microblog:user:1", "avatar") == "assets/avatars/avatar-08.jpg"
    settings, metadata = request(alice_session, query="view=settings")
    assert "status=200" in metadata
    assert 'value="assets/avatars/avatar-08.jpg" checked' in settings
    assert 'enctype="multipart/form-data"' in settings
    assert '<h1>AI Bot</h1>' in settings
    assert 'name="action" value="save_bot_settings"' in settings
    assert 'id="bot-enabled"' in settings
    assert 'class="panel settings-panel session-settings"' in settings
    assert settings.index("<h1>Edit profile</h1>") < settings.index("<h1>AI Bot</h1>") < settings.index("<h1>Session</h1>")
    assert settings.count('class="visibility-toggle"') == 3
    assert 'id="bot-endpoint" type="password"' in settings
    assert 'id="bot-model" type="password"' in settings
    assert 'id="bot-api-key" type="password"' in settings

    _, metadata = post(
        alice_session,
        "save_bot_settings",
        {
            "bot_endpoint": "https://api.example.invalid/v1",
            "bot_model": "example-chat-large",
            "bot_api_key": "secret-test-api-key",
            "bot_enabled": "1",
        },
    )
    assert_redirect(metadata)
    assert redis("HGET", "openasp:microblog:user:1", "bot_endpoint") == "https://api.example.invalid/v1"
    assert redis("HGET", "openasp:microblog:user:1", "bot_model") == "example-chat-large"
    assert redis("HGET", "openasp:microblog:user:1", "bot_api_key") == "secret-test-api-key"
    assert redis("HGET", "openasp:microblog:user:1", "bot_enabled") == "1"

    settings, metadata = request(alice_session, query="view=settings")
    assert "status=200" in metadata
    assert 'value="https://api.example.invalid/v1"' in settings
    assert 'value="example-chat-large"' in settings
    assert 'data-has-key="1"' in settings
    assert 'id="bot-enabled" type="checkbox" name="bot_enabled" value="1" checked' in settings
    assert 'value="secret-test-api-key"' in settings
    assert 'data-visibility-target="bot-api-key"' in settings

    _, metadata = post(
        alice_session,
        "save_bot_settings",
        {
            "bot_endpoint": "https://api.example.invalid/v2",
            "bot_model": "example-chat-next",
            "bot_api_key": "",
            "bot_enabled": "1",
        },
    )
    assert_redirect(metadata)
    assert redis("HGET", "openasp:microblog:user:1", "bot_endpoint") == "https://api.example.invalid/v2"
    assert redis("HGET", "openasp:microblog:user:1", "bot_model") == "example-chat-next"
    assert redis("HGET", "openasp:microblog:user:1", "bot_api_key") == "secret-test-api-key"

    _, metadata = post(
        alice_session,
        "save_bot_settings",
        {
            "bot_endpoint": "javascript:alert(1)",
            "bot_model": "blocked-model",
            "bot_api_key": "",
            "bot_enabled": "1",
        },
    )
    assert_redirect(metadata)
    assert redis("HGET", "openasp:microblog:user:1", "bot_endpoint") == "https://api.example.invalid/v2"
    assert redis("HGET", "openasp:microblog:user:1", "bot_model") == "example-chat-next"

    ajax_payload, metadata = post_ajax(
        alice_session,
        "publish",
        {"body": "Emoji 😀 #OpenASP# #Security# <script>alert('unsafe')</script>"},
    )
    assert "status=200" in metadata, metadata
    assert ajax_payload["ok"] is True
    assert ajax_payload["post_id"] == "3"
    redis(
        "HSET",
        "openasp:microblog:post:3",
        "image",
        "assets/avatars/avatar-03.jpg",
        "link_url",
        "https://microblog.example.invalid/docs?q=asp&mode=rich",
        "link_label",
        "OpenASP documentation",
    )
    assert redis("ZSCORE", "openasp:microblog:topics:counts", "openasp") == "2"
    assert redis("ZSCORE", "openasp:microblog:topics:counts", "security") == "1"
    discover, metadata = request(bob_session, query="view=discover")
    assert "status=200" in metadata
    assert "Emoji 😀" in discover
    assert "&lt;script&gt;alert(&#39;unsafe&#39;)&lt;/script&gt;" in discover
    assert "<script>alert('unsafe')</script>" not in discover
    assert 'class="post-image" src="assets/avatars/avatar-03.jpg"' in discover
    assert 'href="https://microblog.example.invalid/docs?q=asp&amp;mode=rich"' in discover
    assert "OpenASP documentation" in discover

    redis("HSET", "openasp:microblog:post:3", "link_url", "javascript:alert(1)")
    unsafe_link_page, metadata = request(bob_session, query="view=discover")
    assert "status=200" in metadata
    assert "javascript:alert(1)" not in unsafe_link_page
    redis("HSET", "openasp:microblog:post:3", "link_url", "https://microblog.example.invalid/docs")

    _, metadata = post(alice_session, "logout", {})
    assert_redirect(metadata)
    assert remember_tokens_for("1") == []
    assert len(remember_tokens_for("2")) == 1
    signed_out, metadata = request(alice_session, query="view=auth")
    assert "status=200" in metadata
    assert "You are signed out." in signed_out
    assert "Connect everything. Hear the world's voice." in signed_out
    assert 'type="email" name="email"' in signed_out

    login_token = csrf(alice_session)
    _, metadata = request(
        alice_session,
        form={
            "action": "login",
            "csrf": login_token,
            "username": "alice",
            "password": "correct-horse",
        },
    )
    assert_redirect(metadata)
    alice_tokens = remember_tokens_for("1")
    assert len(alice_tokens) == 1
    assert 2591900 <= int(redis("TTL", alice_tokens[0])) <= 2592000
    signed_in, metadata = request(alice_session)
    assert "status=200" in metadata
    assert "Welcome back, Alice C.." in signed_in
    assert "You can connect everything. Hear the world's voice." in signed_in

    _, metadata = post(alice_session, "delete_post", {"post_id": "3"})
    assert_redirect(metadata)
    assert redis("EXISTS", "openasp:microblog:post:3") == "0"
    assert redis("LRANGE", "openasp:microblog:posts:global", "0", "-1") == "2\n1"
    assert redis("ZSCORE", "openasp:microblog:topics:counts", "openasp") == "1"
    assert redis("ZSCORE", "openasp:microblog:topics:counts", "security") == ""
    assert redis("EXISTS", "openasp:microblog:topic:security:posts") == "0"

    _, metadata = post(alice_session, "unfollow", {"target_id": "2"})
    assert_redirect(metadata)
    assert redis("SISMEMBER", "openasp:microblog:following:1", "2") == "0"
    assert redis("SISMEMBER", "openasp:microblog:followers:2", "1") == "0"

    for post_id in range(4, 15):
        redis(
            "HSET",
            f"openasp:microblog:post:{post_id}",
            "author_id",
            "2",
            "body",
            f"Pagination post {post_id}",
            "created_at",
            "2026-10-06 01:00",
        )
        redis("LPUSH", "openasp:microblog:posts:global", str(post_id))
        redis("LPUSH", "openasp:microblog:user:2:posts", str(post_id))
    redis("SET", "openasp:microblog:next:post", "14")

    discover_page_one, metadata = request(bob_session, query="view=discover")
    assert "status=200" in metadata
    assert discover_page_one.count('class="post-card"') == 10
    assert 'class="feed-page-sentinel"' in discover_page_one
    assert 'data-feed-kind="discover"' in discover_page_one
    assert 'data-page="2"' in discover_page_one
    assert "<noscript>" in discover_page_one
    assert ">Next page</a>" in discover_page_one
    assert "Load more" not in discover_page_one
    assert "Pagination post 14" in discover_page_one
    assert "Pagination post 4" not in discover_page_one

    discover_page_two, metadata = request(bob_session, query="view=discover&page=2")
    assert "status=200" in metadata
    assert discover_page_two.count('class="post-card"') == 3
    assert "Pagination post 4" in discover_page_two
    assert ">Previous</a>" in discover_page_two
    assert 'class="feed-page-sentinel"' not in discover_page_two
    assert "Load more" not in discover_page_two

    page_fragment, metadata = request(
        bob_session,
        page="feed-page.asp",
        query="kind=discover&page=2",
    )
    assert "status=200" in metadata
    assert page_fragment.count('class="post-card"') == 3
    assert "Pagination post 4" in page_fragment

    bob_home, metadata = request(bob_session)
    assert "status=200" in metadata
    assert bob_home.count('class="post-card"') == 10
    assert 'data-feed-kind="home"' in bob_home

    bob_profile, metadata = request(bob_session, query="view=profile&id=2")
    assert "status=200" in metadata
    assert bob_profile.count('class="post-card"') == 10
    assert 'data-feed-kind="profile"' in bob_profile
    assert 'data-feed-id="2"' in bob_profile

    cache_name = "post-2-11111111111111111111111111111111.jpg"
    cache_storage_path = f"assets/uploads/{cache_name}"
    cache_file = SITE / cache_storage_path
    cache_key = (
        "openasp:microblog:image-cache:"
        + hashlib.sha256(cache_storage_path.lower().encode()).hexdigest()
    )
    source_image = (SITE / "assets/avatars/avatar-01.jpg").read_bytes()
    try:
        cache_file.write_bytes(source_image)
        assert redis("DEL", cache_key) == "0"

        image_body, metadata = request_binary(
            bob_session,
            page="image.asp",
            query=urlencode({"name": cache_name}),
        )
        assert "status=200" in metadata
        assert image_body == source_image
        assert redis("STRLEN", cache_key) == str(len(source_image))
        assert 2591900 <= int(redis("TTL", cache_key)) <= 2592000

        cache_file.unlink()
        cached_body, metadata = request_binary(
            bob_session,
            page="image.asp",
            query=urlencode({"name": cache_name}),
        )
        assert "status=200" in metadata
        assert cached_body == source_image

        redis("HSET", "openasp:microblog:post:14", "image", cache_storage_path)
        cached_image_page, metadata = request(bob_session, query="view=discover")
        assert "status=200" in metadata
        assert f'src="image.asp?name={cache_name}"' in cached_image_page
        redis("HDEL", "openasp:microblog:post:14", "image")

        assert redis("DEL", cache_key) == "1"
        missing_body, metadata = request_binary(
            bob_session,
            page="image.asp",
            query=urlencode({"name": cache_name}),
        )
        assert "status=404" in metadata
        assert missing_body.strip() == b"Image not found."
    finally:
        cache_file.unlink(missing_ok=True)
        redis("DEL", cache_key)
        redis("HDEL", "openasp:microblog:post:14", "image")

    print(f"PASS: uYasoo 30-day Redis image cache, AJAX pagination, bot settings, sign-out, required unique email, 30-day login, rich posts, feed updates, captcha, avatars, mentions, topics, social graph, and safety (optimize={OPTIMIZE})")


if __name__ == "__main__":
    main()
