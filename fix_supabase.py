import re

def process(commit, metadata):
    for file_change in commit.file_changes:
        if file_change.filename == b'lib/supabase.ts':
            content = file_change.data
            # Replace hardcoded URL with process.env
            content = re.sub(
                rb"const SUPABASE_URL = '[^']+';\n",
                rb'const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;\n',
                content
            )
            # Replace hardcoded key with process.env
            content = re.sub(
                rb"const SUPABASE_ANON_KEY = '[^']+';\n",
                rb'const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!;\n',
                content
            )
            file_change.data = content