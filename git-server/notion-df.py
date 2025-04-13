#!/usr/bin/env python3
#  Copyright (c) 2025. Anshul Gupta
#  All rights reserved.

from dotenv import load_dotenv
import subprocess
import requests
import os
import time

# Load environment variables from .env file
load_dotenv(dotenv_path="/srv/git/.env.notion")
NOTION_TOKEN = os.getenv("NOTION_TOKEN")
if NOTION_TOKEN is None:
    raise ValueError("NOTION_TOKEN not found in .env file")
DATABASE_ID = os.getenv("DATABASE_ID")
if DATABASE_ID is None:
    raise ValueError("DATABASE_ID not found in .env file")

headers = {
    "Authorization": f"Bearer {NOTION_TOKEN}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json"
}


def get_df_data():
    output = subprocess.check_output(["df", "-T"]).decode("utf-8").strip().split("\n")
    entries = []
    for line in output[1:]:  # Skip header
        parts = line.split()
        if len(parts) >= 7:
            entries.append({
                "Filesystem": parts[0],
                "Type": parts[1],
                "Size": int(parts[2]),
                "Used": int(parts[3]),
                "Avail": int(parts[4]),
                "Use%": int(parts[5][:-1]) / 100.0,  # Remove the '%' sign
                "Mounted on": parts[6],
            })
    return entries


def query_existing_filesystem(mount_path):
    url = f"https://api.notion.com/v1/databases/{DATABASE_ID}/query"
    payload = {
        "filter": {
            "property": "Mounted On",
            "title": {
                "equals": mount_path
            }
        }
    }
    res = requests.post(url, json=payload, headers=headers)
    if res.status_code != 200:
        print(res.json()["message"])
    res.raise_for_status()
    results = res.json().get("results", [])
    return results[0]["id"] if results else None


def update_page(page_id, entry):
    url = f"https://api.notion.com/v1/pages/{page_id}"
    payload = {
        "properties": {
            "Filesystem": {"rich_text": [{"text": {"content": entry["Filesystem"]}, "annotations": {"code": True}}]},
            "Type": {"select": {"name": entry["Type"]}},
            "Size": {"number": entry["Size"]},
            "Used": {"number": entry["Used"]},
            "Available": {"number": entry["Avail"]},
            "Usage": {"number": entry["Use%"]},
        }
    }
    res = requests.patch(url, json=payload, headers=headers)
    if res.status_code != 200:
        print(res.json()["message"])
    res.raise_for_status()


def create_page(entry):
    url = "https://api.notion.com/v1/pages"
    payload = {
        "parent": {"database_id": DATABASE_ID},
        "properties": {
            "Mounted On": {"title": [{"text": {"content": entry["Mounted on"]}}]},
            "Filesystem": {"rich_text": [{"text": {"content": entry["Filesystem"]}, "annotations": {"code": True}}]},
            "Type": {"select": {"name": entry["Type"]}},
            "Size": {"number": entry["Size"]},
            "Used": {"number": entry["Used"]},
            "Available": {"number": entry["Avail"]},
            "Usage": {"number": entry["Use%"]},
        }
    }
    res = requests.post(url, json=payload, headers=headers)
    if res.status_code != 200:
        print(res.json()["message"])
    res.raise_for_status()


def sync_df_to_notion():
    entries = get_df_data()
    for entry in entries:
        page_id = query_existing_filesystem(entry["Mounted on"])
        if page_id:
            update_page(page_id, entry)
        else:
            create_page(entry)
        time.sleep(0.5)  # Notion API rate limiting


if __name__ == "__main__":
    sync_df_to_notion()
