//! Reminding a borrower that a book is due (8/25 request).
//!
//! The two properties worth defending: **nothing is sent unless somebody asked
//! for it** — no mailer, or reminders switched off, or this loan opted out, and
//! the sweep does nothing — and **each reminder goes once**. A daily nag is how
//! a feature like this gets switched off for good.

use vellum_server::reminders::{days_until, stage_for};

#[test]
fn a_loan_due_further_off_than_the_lead_time_is_left_alone() {
    assert_eq!(stage_for(10, 3), None);
    assert_eq!(stage_for(4, 3), None);
}

#[test]
fn the_first_reminder_goes_inside_the_lead_time() {
    assert_eq!(stage_for(3, 3), Some("before"));
    assert_eq!(stage_for(1, 3), Some("before"));
}

#[test]
fn a_server_that_was_off_still_sends_the_early_one_late() {
    // The window is what makes this work: a server down on the third day
    // before should still say something on the second, because the point is
    // that the reminder arrives, not that it arrives on a particular morning.
    assert_eq!(stage_for(2, 3), Some("before"));
}

#[test]
fn the_day_it_is_due_has_its_own_message() {
    assert_eq!(stage_for(0, 3), Some("due"));
}

#[test]
fn and_after_that_it_is_overdue() {
    assert_eq!(stage_for(-1, 3), Some("overdue"));
    assert_eq!(stage_for(-30, 3), Some("overdue"));
}

#[test]
fn a_lead_time_of_zero_means_no_warning_shot() {
    assert_eq!(stage_for(1, 0), None);
    assert_eq!(stage_for(0, 0), Some("due"));
}

#[test]
fn days_are_counted_by_date_not_by_hour() {
    // A book due "tomorrow" is due tomorrow whether it was lent at nine in the
    // morning or at five to midnight.
    assert_eq!(
        days_until("2026-08-25 09:00:00", "2026-08-26 01:00:00"),
        Some(1)
    );
    assert_eq!(
        days_until("2026-08-25 23:55:00", "2026-08-26 00:05:00"),
        Some(1)
    );
    assert_eq!(
        days_until("2026-08-25 12:00:00", "2026-08-25 23:00:00"),
        Some(0)
    );
}

#[test]
fn a_date_in_the_past_counts_backwards() {
    assert_eq!(
        days_until("2026-08-25 12:00:00", "2026-08-20 12:00:00"),
        Some(-5)
    );
}

#[test]
fn a_timestamp_that_is_not_one_is_skipped_rather_than_guessed_at() {
    assert_eq!(days_until("2026-08-25 12:00:00", "sometime soon"), None);
    assert_eq!(days_until("", "2026-08-26 00:00:00"), None);
}

#[test]
fn a_template_says_what_it_was_given() {
    use vellum_server::settings::render;
    let out = render(
        "\"{title}\" is due back on {due_date}, {borrower}.",
        &[
            ("title", "Dune"),
            ("due_date", "2026-08-29"),
            ("borrower", "Ana"),
        ],
    );
    assert_eq!(out, "\"Dune\" is due back on 2026-08-29, Ana.");
}

#[test]
fn a_placeholder_nobody_filled_stays_visible() {
    use vellum_server::settings::render;
    // A message reading "due back on {due_date}" is a bug report. One reading
    // "due back on" is a mystery.
    let out = render("due back on {due_date}", &[("title", "Dune")]);
    assert_eq!(out, "due back on {due_date}");
}

#[test]
fn the_stock_messages_name_the_book_and_the_date() {
    use vellum_server::settings::{
        REMINDER_BEFORE_BODY, REMINDER_DUE_BODY, REMINDER_OVERDUE_BODY, default_for,
    };
    for key in [
        REMINDER_BEFORE_BODY,
        REMINDER_DUE_BODY,
        REMINDER_OVERDUE_BODY,
    ] {
        let body = default_for(key);
        assert!(body.contains("{title}"), "{key} should name the book");
        assert!(body.contains("{borrower}"), "{key} should greet somebody");
    }
    assert!(default_for(REMINDER_BEFORE_BODY).contains("{due_date}"));
}

#[test]
fn reminders_are_off_until_somebody_switches_them_on() {
    use vellum_server::settings::{LOAN_REMINDERS, default_for};
    // A server that starts emailing the moment it learns how to is a server
    // nobody forgives.
    assert_eq!(default_for(LOAN_REMINDERS), "off");
}
