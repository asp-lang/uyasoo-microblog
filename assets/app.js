// Copyright (c) 2026 https://uyasoo.com
// SPDX-License-Identifier: MIT

"use strict";

const formControlSelector = "input, textarea, select";

const englishValidationMessage = (control) => {
    const validity = control.validity;
    if (validity.valueMissing) {
        if (control.type === "file") return "Choose a file.";
        if (control.type === "checkbox" || control.type === "radio") return "Select this option.";
        return "Complete this field.";
    }
    if (validity.typeMismatch) {
        if (control.type === "email") return "Enter a valid email address.";
        if (control.type === "url") return "Enter a valid URL.";
    }
    if (validity.patternMismatch) return "Use the requested format.";
    if (validity.tooShort) return `Use at least ${control.minLength} characters.`;
    if (validity.tooLong) return `Use no more than ${control.maxLength} characters.`;
    if (validity.rangeUnderflow) return `Enter a value of at least ${control.min}.`;
    if (validity.rangeOverflow) return `Enter a value no greater than ${control.max}.`;
    if (validity.badInput) return "Enter a valid value.";
    return "Check this value.";
};

const syncEnglishValidationMessage = (control) => {
    control.setCustomValidity("");
    if (!control.validity.valid) {
        control.setCustomValidity(englishValidationMessage(control));
    }
};

document.addEventListener(
    "invalid",
    (event) => {
        const control = event.target;
        if (!control.matches?.(formControlSelector)) return;
        syncEnglishValidationMessage(control);
    },
    true,
);

document.addEventListener(
    "focusin",
    (event) => {
        const control = event.target;
        if (control.matches?.(formControlSelector)) {
            syncEnglishValidationMessage(control);
        }
    },
    true,
);

document.addEventListener("input", (event) => {
    if (event.target.matches?.(formControlSelector)) syncEnglishValidationMessage(event.target);
});

document.addEventListener("change", (event) => {
    if (event.target.matches?.(formControlSelector)) syncEnglishValidationMessage(event.target);
});

document.querySelectorAll(formControlSelector).forEach(syncEnglishValidationMessage);
document.querySelectorAll("form").forEach((form) => {
    form.noValidate = true;
});

const captchaImage = document.querySelector("#register-captcha");
const refreshCaptcha = document.querySelector("#refresh-captcha");

if (captchaImage && refreshCaptcha) {
    refreshCaptcha.addEventListener("click", () => {
        captchaImage.src = `captcha.asp?t=${Date.now()}`;
    });
}

const botEnabled = document.querySelector("#bot-enabled");

if (botEnabled) {
    const botEndpoint = document.querySelector("#bot-endpoint");
    const botModel = document.querySelector("#bot-model");
    const botApiKey = document.querySelector("#bot-api-key");
    const updateBotRequirements = () => {
        botEndpoint.required = botEnabled.checked;
        botModel.required = botEnabled.checked;
        botApiKey.required = botEnabled.checked && botApiKey.dataset.hasKey !== "1";
    };
    botEnabled.addEventListener("change", updateBotRequirements);
    updateBotRequirements();
}

document.querySelectorAll(".visibility-toggle").forEach((button) => {
    button.addEventListener("click", () => {
        const input = document.querySelector(`#${button.dataset.visibilityTarget}`);
        if (!input) return;
        const shouldShow = input.type === "password";
        const action = shouldShow ? "Hide" : "Show";
        const label = button.dataset.visibilityLabel;
        input.type = shouldShow ? "text" : "password";
        button.setAttribute("aria-pressed", String(shouldShow));
        button.setAttribute("aria-label", `${action} ${label}`);
        button.title = `${action} ${label}`;
        input.focus();
    });
});

const showAjaxNotice = (message, kind = "success") => {
    let notice = document.querySelector("#ajax-notice");
    if (!notice) {
        notice = document.createElement("div");
        notice.id = "ajax-notice";
        notice.className = "ajax-notice";
        document.body.append(notice);
    }
    notice.classList.toggle("ajax-notice-error", kind === "error");
    notice.setAttribute("role", kind === "error" ? "alert" : "status");
    notice.textContent = message;
    notice.hidden = !message;
    window.clearTimeout(showAjaxNotice.timer);
    if (message) {
        showAjaxNotice.timer = window.setTimeout(() => {
            notice.hidden = true;
        }, 2000);
    }
};

const fetchPostCard = async (postId, showComments) => {
    const response = await fetch(
        `post-fragment.asp?id=${encodeURIComponent(postId)}&comments=${showComments ? "1" : "0"}`,
        {
            credentials: "same-origin",
            cache: "no-store",
        },
    );
    if (!response.ok) throw new Error("The post could not be refreshed.");
    const template = document.createElement("template");
    template.innerHTML = (await response.text()).trim();
    const card = template.content.querySelector(".post-card");
    if (!card) throw new Error("The post response was incomplete.");
    return card;
};

const refreshPostCard = async (postId) => {
    const current = document.querySelector(`.post-card[data-post-id="${CSS.escape(String(postId))}"]`);
    if (!current) return null;
    const replacement = await fetchPostCard(postId, Boolean(current.querySelector(".comments")));
    current.replaceWith(replacement);
    setupMentionFields(replacement);
    return replacement;
};

const prependPublishedPost = async (postId) => {
    const card = await fetchPostCard(postId, false);
    const feedList = document.querySelector("#feed-list");
    if (!feedList) return;

    const existing = feedList.querySelector(
        `.post-card[data-post-id="${CSS.escape(String(postId))}"]`,
    );
    card.classList.add("post-card-enter");
    if (existing) {
        existing.replaceWith(card);
    } else {
        feedList.querySelector(".empty-state")?.remove();
        feedList.prepend(card);
    }
};

const feedUpdateBar = document.querySelector("#feed-update-bar");

if (feedUpdateBar) {
    const updateLabel = feedUpdateBar.querySelector(".feed-update-label");
    const updateCount = feedUpdateBar.querySelector(".feed-update-count");
    let loadedId = Number.parseInt(feedUpdateBar.dataset.after || "0", 10) || 0;
    let knownLatestId = loadedId;
    let pendingCount = 0;
    let pollTimer = 0;
    let pollInFlight = false;

    const schedulePoll = () => {
        window.clearTimeout(pollTimer);
        pollTimer = window.setTimeout(pollForUpdates, 60000);
    };

    const pollForUpdates = async () => {
        if (pollInFlight) {
            schedulePoll();
            return;
        }
        if (document.hidden) {
            schedulePoll();
            return;
        }
        pollInFlight = true;
        try {
            const response = await fetch(`feed-updates.asp?after=${knownLatestId}`, {
                credentials: "same-origin",
                headers: { Accept: "application/json" },
                cache: "no-store",
            });
            if (response.status === 401) {
                window.location.assign("/?view=auth");
                return;
            }
            if (!response.ok) return;
            const payload = await response.json();
            const nextLatestId = Number.parseInt(payload.latest_id, 10);
            const newCount = Number.parseInt(payload.count, 10);
            if (Number.isFinite(nextLatestId) && nextLatestId > knownLatestId) {
                knownLatestId = nextLatestId;
            }
            if (Number.isFinite(newCount) && newCount > 0) {
                pendingCount += newCount;
                updateLabel.textContent = pendingCount === 1 ? "1 new post" : `${pendingCount} new posts`;
                updateCount.textContent = "Refresh";
                feedUpdateBar.hidden = false;
            }
        } catch {
            // A later poll retries transient network and parsing failures.
        } finally {
            pollInFlight = false;
            schedulePoll();
        }
    };

    const loadFeedUpdates = async () => {
        if (feedUpdateBar.disabled) return;
        feedUpdateBar.disabled = true;
        feedUpdateBar.setAttribute("aria-busy", "true");
        try {
            const response = await fetch(`feed-fragment.asp?after=${loadedId}`, {
                credentials: "same-origin",
                cache: "no-store",
            });
            if (response.status === 401) {
                window.location.assign("/?view=auth");
                return;
            }
            if (!response.ok) throw new Error("New posts could not be loaded.");
            const template = document.createElement("template");
            template.innerHTML = await response.text();
            const cards = [...template.content.querySelectorAll(".post-card")];
            const feedList = document.querySelector("#feed-list");
            if (feedList && cards.length) {
                feedList.querySelector(".empty-state")?.remove();
                const unseenCards = cards.filter(
                    (card) =>
                        !feedList.querySelector(
                            `.post-card[data-post-id="${CSS.escape(card.dataset.postId)}"]`,
                        ),
                );
                feedList.prepend(...unseenCards);
            }
            const responseLatestId = Number.parseInt(
                response.headers.get("X-Latest-Post-Id") || "",
                10,
            );
            if (Number.isFinite(responseLatestId)) {
                loadedId = Math.max(loadedId, responseLatestId);
                knownLatestId = Math.max(knownLatestId, responseLatestId);
            }
            pendingCount = 0;
            feedUpdateBar.hidden = true;
        } catch (error) {
            showAjaxNotice(error.message, "error");
        } finally {
            feedUpdateBar.disabled = false;
            feedUpdateBar.removeAttribute("aria-busy");
        }
    };

    feedUpdateBar.addEventListener("click", loadFeedUpdates);
    document.addEventListener("feed:post-added", (event) => {
        const postId = Number.parseInt(event.detail?.postId || "0", 10);
        if (postId > 0) {
            knownLatestId = Math.max(knownLatestId, postId);
        }
    });
    document.addEventListener("visibilitychange", () => {
        if (!document.hidden) {
            window.clearTimeout(pollTimer);
            pollForUpdates();
        }
    });
    schedulePoll();
}

let feedPageObserver = null;

const observeFeedPageSentinel = (sentinel) => {
    if (!sentinel) return;
    if (feedPageObserver) {
        feedPageObserver.observe(sentinel);
        return;
    }

    const checkPosition = () => {
        if (!sentinel.isConnected) {
            window.removeEventListener("scroll", checkPosition);
            window.removeEventListener("resize", checkPosition);
            return;
        }
        if (sentinel.getBoundingClientRect().top > window.innerHeight + 400) return;
        window.removeEventListener("scroll", checkPosition);
        window.removeEventListener("resize", checkPosition);
        loadNextFeedPage(sentinel);
    };
    window.addEventListener("scroll", checkPosition, { passive: true });
    window.addEventListener("resize", checkPosition);
    checkPosition();
};

const retryFeedPageAfterLeavingBoundary = (sentinel) => {
    const rearm = () => {
        if (!sentinel.isConnected) {
            window.removeEventListener("scroll", rearm);
            return;
        }
        if (sentinel.getBoundingClientRect().top <= window.innerHeight + 400) return;
        window.removeEventListener("scroll", rearm);
        observeFeedPageSentinel(sentinel);
    };
    window.addEventListener("scroll", rearm, { passive: true });
};

const loadNextFeedPage = async (sentinel) => {
    if (sentinel.dataset.loading === "1") return;
    const pagination = sentinel.closest(".feed-pagination");
    const feedList = document.querySelector("#feed-list");
    if (!pagination || !feedList) return;

    feedPageObserver?.unobserve(sentinel);
    sentinel.dataset.loading = "1";
    pagination.setAttribute("aria-busy", "true");
    try {
        const params = new URLSearchParams({
            kind: sentinel.dataset.feedKind || "",
            id: sentinel.dataset.feedId || "",
            page: sentinel.dataset.page || "1",
        });
        const response = await fetch(`feed-page.asp?${params}`, {
            credentials: "same-origin",
            cache: "no-store",
        });
        if (!response.ok) throw new Error("More posts could not be loaded.");

        const template = document.createElement("template");
        template.innerHTML = await response.text();
        const cards = [...template.content.querySelectorAll(".post-card")];
        const unseenCards = cards.filter(
            (card) =>
                !feedList.querySelector(
                    `.post-card[data-post-id="${CSS.escape(card.dataset.postId)}"]`,
                ),
        );
        feedList.append(...unseenCards);
        feedList.dataset.page = sentinel.dataset.page;

        const nextPagination = template.content.querySelector(".feed-pagination");
        const nextSentinel = nextPagination?.querySelector(".feed-page-sentinel");
        if (nextSentinel) {
            pagination.replaceWith(nextPagination);
            observeFeedPageSentinel(nextSentinel);
        } else {
            pagination.remove();
        }
    } catch (error) {
        delete sentinel.dataset.loading;
        pagination.removeAttribute("aria-busy");
        showAjaxNotice(error.message || "More posts could not be loaded.", "error");
        retryFeedPageAfterLeavingBoundary(sentinel);
    }
};

if ("IntersectionObserver" in window) {
    feedPageObserver = new IntersectionObserver(
        (entries) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) loadNextFeedPage(entry.target);
            });
        },
        { rootMargin: "0px 0px 400px" },
    );
}

observeFeedPageSentinel(document.querySelector(".feed-page-sentinel"));

const composer = document.querySelector("#post-composer");

if (composer) {
    const bodyField = composer.querySelector("#post-body");
    const characterCount = composer.querySelector("#post-character-count");
    const imageInput = composer.querySelector("#post-image-input");
    const imagePreview = composer.querySelector("#post-image-preview");
    const previewImage = imagePreview.querySelector("img");
    const previewName = imagePreview.querySelector("strong");
    const previewSize = imagePreview.querySelector("span");
    const removeImage = imagePreview.querySelector("button");
    const linkUrl = composer.querySelector('input[name="link_url"]');
    const linkLabel = composer.querySelector('input[name="link_label"]');
    const errorBox = composer.querySelector("#composer-error");
    const toggleButtons = [...composer.querySelectorAll("[data-composer-toggle]")];
    const panels = [...composer.querySelectorAll("[data-composer-panel]")];
    let previewUrl = "";

    const showError = (message) => {
        errorBox.textContent = message;
        errorBox.hidden = !message;
    };

    const closePanels = (except = "") => {
        panels.forEach((panel) => {
            if (panel.dataset.composerPanel !== except) panel.hidden = true;
        });
        toggleButtons.forEach((button) => {
            button.setAttribute("aria-expanded", String(button.dataset.composerToggle === except));
        });
    };

    const clearImage = () => {
        if (previewUrl) URL.revokeObjectURL(previewUrl);
        previewUrl = "";
        imageInput.value = "";
        previewImage.removeAttribute("src");
        imagePreview.hidden = true;
    };

    bodyField.addEventListener("input", () => {
        characterCount.textContent = String(bodyField.value.length);
        showError("");
    });

    toggleButtons.forEach((button) => {
        button.addEventListener("click", () => {
            const panel = composer.querySelector(
                `[data-composer-panel="${button.dataset.composerToggle}"]`,
            );
            const shouldOpen = panel.hidden;
            closePanels(shouldOpen ? button.dataset.composerToggle : "");
            panel.hidden = !shouldOpen;
            if (shouldOpen && button.dataset.composerToggle === "link") linkUrl.focus();
        });
    });

    composer.querySelectorAll(".emoji-picker button").forEach((button) => {
        button.addEventListener("click", () => {
            const start = bodyField.selectionStart;
            const end = bodyField.selectionEnd;
            bodyField.setRangeText(button.textContent, start, end, "end");
            bodyField.dispatchEvent(new Event("input", { bubbles: true }));
            bodyField.focus();
        });
    });

    imageInput.addEventListener("change", () => {
        const file = imageInput.files[0];
        clearImage();
        if (!file) return;
        if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
            showError("Choose a JPG, PNG, or WebP image.");
            return;
        }
        if (file.size > 5 * 1024 * 1024) {
            showError("The post image must not exceed 5 MB.");
            return;
        }
        const transfer = new DataTransfer();
        transfer.items.add(file);
        imageInput.files = transfer.files;
        previewUrl = URL.createObjectURL(file);
        previewImage.src = previewUrl;
        previewName.textContent = file.name;
        previewSize.textContent = `${(file.size / 1024).toFixed(file.size >= 1024 ? 0 : 1)} KB`;
        imagePreview.hidden = false;
        showError("");
    });

    removeImage.addEventListener("click", clearImage);
    linkUrl.addEventListener("input", () => showError(""));
    linkLabel.addEventListener("input", () => showError(""));

    composer.addEventListener("submit", (event) => {
        const hasBody = bodyField.value.trim() !== "";
        const hasImage = imageInput.files.length > 0;
        const hasLink = linkUrl.value.trim() !== "";
        if (!hasBody && !hasImage && !hasLink) {
            event.preventDefault();
            showError("Add text, an image, or a link before posting.");
            bodyField.focus();
            return;
        }
        if (linkLabel.value.trim() && !hasLink) {
            event.preventDefault();
            showError("Add a URL for the link label.");
            linkUrl.focus();
        }
    });

    composer.addEventListener("ajax:success", () => {
        composer.reset();
        characterCount.textContent = "0";
        clearImage();
        closePanels();
        showError("");
        bodyField.focus();
    });

    document.addEventListener("pointerdown", (event) => {
        if (!composer.querySelector(".composer-tools").contains(event.target)) closePanels();
    });
}

const setupMentionField = (field) => {
    if (field.dataset.mentionReady === "1") return;
    field.dataset.mentionReady = "1";
    const wrapper = document.createElement("div");
    const menu = document.createElement("div");
    const menuId = `mention-menu-${setupMentionField.nextId++}`;
    let matches = [];
    let activeIndex = 0;
    let mentionStart = -1;
    let requestController = null;
    let requestTimer = 0;

    wrapper.className = "mention-input-wrap";
    menu.className = "mention-menu";
    menu.id = menuId;
    menu.hidden = true;
    menu.setAttribute("role", "listbox");
    field.parentNode.insertBefore(wrapper, field);
    wrapper.append(field, menu);
    field.setAttribute("role", "combobox");
    field.setAttribute("aria-autocomplete", "list");
    field.setAttribute("aria-controls", menuId);
    field.setAttribute("aria-expanded", "false");

    const closeMenu = () => {
        menu.hidden = true;
        menu.replaceChildren();
        field.setAttribute("aria-expanded", "false");
        field.removeAttribute("aria-activedescendant");
        matches = [];
        activeIndex = 0;
    };

    const setActive = (index) => {
        const options = [...menu.querySelectorAll(".mention-option")];
        if (!options.length) return;
        activeIndex = (index + options.length) % options.length;
        options.forEach((option, optionIndex) => {
            const selected = optionIndex === activeIndex;
            option.classList.toggle("active", selected);
            option.setAttribute("aria-selected", String(selected));
        });
        field.setAttribute("aria-activedescendant", options[activeIndex].id);
        options[activeIndex].scrollIntoView({ block: "nearest" });
    };

    const chooseUser = (user) => {
        const cursor = field.selectionStart;
        field.value = `${field.value.slice(0, mentionStart)}@${user.username} ${field.value.slice(cursor)}`;
        const nextCursor = mentionStart + user.username.length + 2;
        field.setSelectionRange(nextCursor, nextCursor);
        field.focus();
        closeMenu();
        field.dispatchEvent(new Event("input", { bubbles: true }));
    };

    const renderMatches = (users) => {
        matches = users;
        menu.replaceChildren();
        if (!users.length) {
            closeMenu();
            return;
        }
        users.forEach((user, index) => {
            const option = document.createElement("button");
            const avatar = document.createElement("img");
            const copy = document.createElement("span");
            const name = document.createElement("strong");
            const handle = document.createElement("small");

            option.type = "button";
            option.className = "mention-option";
            option.id = `${menuId}-option-${index}`;
            option.setAttribute("role", "option");
            avatar.src = user.avatar;
            avatar.alt = "";
            name.textContent = user.display_name;
            handle.textContent = `@${user.username}`;
            copy.append(name, handle);
            option.append(avatar, copy);
            option.addEventListener("pointerdown", (event) => {
                event.preventDefault();
                chooseUser(user);
            });
            menu.append(option);
        });
        menu.hidden = false;
        field.setAttribute("aria-expanded", "true");
        setActive(0);
    };

    const searchMentions = () => {
        const cursor = field.selectionStart;
        const beforeCursor = field.value.slice(0, cursor);
        const match = beforeCursor.match(/(?:^|\s)@([^\s@]{0,20})$/u);
        window.clearTimeout(requestTimer);
        requestController?.abort();
        if (!match) {
            closeMenu();
            return;
        }
        mentionStart = cursor - match[1].length - 1;
        requestTimer = window.setTimeout(async () => {
            requestController = new AbortController();
            try {
                const response = await fetch(`mention-users.asp?q=${encodeURIComponent(match[1])}`, {
                    credentials: "same-origin",
                    headers: { Accept: "application/json" },
                    signal: requestController.signal,
                });
                if (!response.ok) {
                    closeMenu();
                    return;
                }
                const payload = await response.json();
                renderMatches(Array.isArray(payload.users) ? payload.users : []);
            } catch (error) {
                if (error.name !== "AbortError") closeMenu();
            }
        }, 120);
    };

    field.addEventListener("input", searchMentions);
    field.addEventListener("click", searchMentions);
    field.addEventListener("keydown", (event) => {
        if (menu.hidden) return;
        if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            event.preventDefault();
            setActive(activeIndex + (event.key === "ArrowDown" ? 1 : -1));
        } else if ((event.key === "Enter" || event.key === "Tab") && matches[activeIndex]) {
            event.preventDefault();
            chooseUser(matches[activeIndex]);
        } else if (event.key === "Escape") {
            event.preventDefault();
            closeMenu();
        }
    });
    field.addEventListener("blur", () => window.setTimeout(closeMenu, 120));
};

setupMentionField.nextId = 0;

function setupMentionFields(root = document) {
    root.querySelectorAll(".composer textarea[name='body'], .comment-form input[name='body']").forEach(
        setupMentionField,
    );
}

setupMentionFields();

const updateFollowControls = (targetId, isFollowing, followerCount) => {
    document
        .querySelectorAll(`form input[name="target_id"][value="${CSS.escape(String(targetId))}"]`)
        .forEach((input) => {
            const form = input.form;
            const action = form.querySelector('input[name="action"]');
            const button = form.querySelector('button[type="submit"]');
            action.value = isFollowing ? "unfollow" : "follow";
            button.textContent = isFollowing ? "Following" : "Follow";
            button.classList.toggle("button-primary", !isFollowing);
            button.classList.toggle("button-secondary", isFollowing);
        });
    const profileCard = document.querySelector(".profile-card");
    if (profileCard) {
        const profileId = new URL(window.location.href).searchParams.get("id");
        if (profileId === String(targetId)) {
            const followerStat = [...profileCard.querySelectorAll(".profile-stats a")].find(
                (link) => link.textContent.includes("Followers"),
            );
            if (followerStat) followerStat.querySelector("strong").textContent = followerCount;
        }
    }
};

const updateVisibleAvatars = (avatar) => {
    document.querySelectorAll(".avatar-settings .avatar").forEach((image) => {
        image.src = avatar;
    });
};

const validateForm = (form) => {
    const controls = [...form.querySelectorAll(formControlSelector)];
    controls.forEach(syncEnglishValidationMessage);
    const invalidControl = controls.find((control) => !control.validity.valid);
    if (!invalidControl) return true;

    showAjaxNotice(invalidControl.validationMessage || "Check this value.", "error");
    invalidControl.focus();
    return false;
};

const submitAjaxForm = async (form) => {
    if (form.dataset.submitting === "1") return;
    const submitButton = form.querySelector('button[type="submit"], input[type="submit"]');
    const formData = new FormData(form);
    const action = String(formData.get("action") || "");
    const endpoint = new URL(form.getAttribute("action") || window.location.href, window.location.href);
    endpoint.searchParams.set("_ajax", "1");
    const isMultipart = form.enctype.toLowerCase() === "multipart/form-data";
    const requestBody = isMultipart ? formData : new URLSearchParams();
    if (!isMultipart) {
        formData.forEach((value, name) => requestBody.append(name, String(value)));
    }
    form.dataset.submitting = "1";
    if (submitButton) {
        submitButton.disabled = true;
        submitButton.setAttribute("aria-busy", "true");
        if (
            submitButton instanceof HTMLButtonElement &&
            (action === "publish" || endpoint.pathname.endsWith("/publish-post.asp"))
        ) {
            submitButton.dataset.idleLabel = submitButton.textContent;
            submitButton.textContent = "Posting...";
        }
    }

    try {
        const response = await fetch(endpoint, {
            method: "POST",
            body: requestBody,
            credentials: "same-origin",
            headers: {
                Accept: "application/json",
                "X-Requested-With": "XMLHttpRequest",
            },
        });
        const responseText = await response.text();
        let payload;
        try {
            payload = JSON.parse(responseText);
        } catch {
            throw new Error("The server returned an unexpected response.");
        }
        if (!response.ok || !payload.ok) {
            if (response.status === 401 && payload.redirect) {
                window.location.assign(payload.redirect);
                return;
            }
            if (action === "register" && captchaImage) {
                captchaImage.src = `captcha.asp?t=${Date.now()}`;
                const captchaField = form.querySelector('input[name="captcha"]');
                if (captchaField) captchaField.value = "";
            }
            throw new Error(payload.message || "The request could not be completed.");
        }

        if (action === "login" || action === "register" || action === "logout") {
            window.location.assign(payload.redirect || "/");
            return;
        }

        if (action === "publish" || endpoint.pathname.endsWith("/publish-post.asp")) {
            form.dispatchEvent(new CustomEvent("ajax:success"));
            document.dispatchEvent(
                new CustomEvent("feed:post-added", { detail: { postId: payload.post_id } }),
            );
            showAjaxNotice(payload.message || "Your post is live.");
            prependPublishedPost(payload.post_id).catch(() => {
                showAjaxNotice("Your post is live. Refresh the feed to see it.");
            });
            return;
        } else if (action === "like" || action === "unlike" || action === "comment") {
            await refreshPostCard(payload.post_id);
        } else if (action === "delete_post") {
            const card = document.querySelector(
                `.post-card[data-post-id="${CSS.escape(String(payload.post_id))}"]`,
            );
            const wasConversation = Boolean(card?.querySelector(".comments"));
            card?.remove();
            if (wasConversation) {
                const emptyState = document.createElement("div");
                emptyState.className = "empty-state";
                emptyState.innerHTML =
                    "<strong>Post deleted</strong><span>The conversation is no longer available.</span>";
                document.querySelector(".content-column")?.append(emptyState);
            } else {
                const feedList = document.querySelector("#feed-list");
                if (feedList && !feedList.querySelector(".post-card")) {
                    feedList.innerHTML =
                        '<div class="empty-state"><strong>No posts yet</strong><span>Follow people or publish the first update.</span></div>';
                }
            }
        } else if (action === "follow" || action === "unfollow") {
            updateFollowControls(
                payload.target_id,
                String(payload.following).toLowerCase() === "true",
                payload.follower_count,
            );
        } else if (action === "select_avatar" || endpoint.pathname.endsWith("/upload-avatar.asp")) {
            updateVisibleAvatars(payload.avatar);
            if (endpoint.pathname.endsWith("/upload-avatar.asp")) form.reset();
        } else if (action === "edit_profile" && payload.display_name) {
            const accountLink = document.querySelector(".account-nav > a");
            if (accountLink) accountLink.textContent = payload.display_name;
        } else if (action === "save_bot_settings") {
            const apiKeyField = form.querySelector('input[name="bot_api_key"]');
            if (apiKeyField?.value) apiKeyField.dataset.hasKey = "1";
        }

        if (payload.message) showAjaxNotice(payload.message);
    } catch (error) {
        showAjaxNotice(error.message || "The request could not be completed.", "error");
    } finally {
        delete form.dataset.submitting;
        if (submitButton?.isConnected) {
            submitButton.disabled = false;
            submitButton.removeAttribute("aria-busy");
            if (submitButton.dataset.idleLabel !== undefined) {
                submitButton.textContent = submitButton.dataset.idleLabel;
                delete submitButton.dataset.idleLabel;
            }
        }
    }
};

document.addEventListener("submit", (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || form.method.toLowerCase() !== "post") return;
    if (event.defaultPrevented) return;
    event.preventDefault();
    if (!validateForm(form)) return;
    submitAjaxForm(form);
});
