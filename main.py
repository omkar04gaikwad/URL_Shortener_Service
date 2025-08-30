import hashlib


url_map = {}

def shorten_url(long_url):
    """ Generate a short code for the given long url and return it"""
    # Create a short hash from url
    long_url_hash = hashlib.sha256(long_url.encode()).hexdigest()[:8]
    url_map[long_url_hash] = long_url
    return long_url_hash


def redirect_url(short_url):
    """ Redirect the given short url to the long url"""
    return url_map.get(short_url)


# ----------------- Example Run -----------------
if __name__ == "__main__":
    url = "https://www.example.com/this-is-a-very-long-url"
    short = shorten_url(url)
    print("Short Code:", short)
    print("Redirect:", redirect_url(short))