---
title: "How it works"
description: "What Copy Fit reads, what it produces, and why it is shaped for a daily check-in."
---

Copy Fit reads your health data from Health Connect and copies it to the
clipboard as JSON, ready to paste into a conversation with ChatGPT or any other
assistant you use as a coach.

## Where the data comes from

Health Connect is part of Android. Apps like Fitbit write your data into it,
and Copy Fit reads it back — only the kinds you allow. The two apps never talk
to each other; Health Connect sits in the middle and checks your permissions on
every read.

## Built for a daily check-in

The default range is the **last 24 hours**. Export in the morning and you get
last night's sleep and nothing older, so each day's paste adds only what is new
to a conversation that already has the rest.

Longer ranges run from 3 days to a year when you want a coach to look at a
trend.

## Two formats

**Daily summary** is one entry per day with each metric rolled up — steps
summed, heart rate as a minimum, average and maximum, weight as the day's last
reading. It is compact enough for a chat message: a month of sleep is a few
thousand tokens.

**Raw points** is every individual reading, for looking closely at a short
stretch.

Before you copy, the app shows the size and an approximate token count, so you
know whether it will fit.

## Sleep, the way a coach needs it

Each night is kept whole. Your longest session is the main sleep, anything else
is a nap, and every session keeps its own start and end along with its deep,
REM, light and awake minutes. A night is filed under the morning you woke up, so
a night that crosses midnight is never split across two days.

## When something is missing

An empty export looks the same whether the permission was denied, nothing is
writing that data, or Health Connect capped the range. So Copy Fit reports every
data type separately — how many readings came back, whether access was granted,
the dates covered, and which app wrote them — and says plainly which of those
it is.

## What it can read

Sleep is selected by default. Everything else is there but opt-in: steps,
distance, floors, active and total calories, workouts, heart rate, resting heart
rate, heart rate variability, weight, body fat, blood oxygen, respiratory rate,
body and skin temperature, blood pressure, blood glucose, water and nutrition.
