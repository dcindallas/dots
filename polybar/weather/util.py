import requests


def get_city() -> str:
    try:
        r = requests.get("https://ipapi.co/json", headers={"User-agent": "Mozilla/5.0"})
        return r.json()["city"]
    except Exception:
        return "frisco"


def unit_suffix(unit: str) -> str:
    match unit:
        case "metric":
            unit = "ºC"
        case "imperial":
            unit = ""
        case _:
            unit = " K"

    return unit
