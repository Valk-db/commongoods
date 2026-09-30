import { supabase } from './supabase';
import * as FileSystem from 'expo-file-system';
import { decode } from 'base64-arraybuffer';

const BUCKET = 'partner-photos';

export async function uploadPhoto(
  localUri: string,
  folder: string,
  fileName: string
): Promise<string | null> {
  try {
    const base64 = await FileSystem.readAsStringAsync(localUri, {
      encoding: 'base64',
    });

    const ext = localUri.split('.').pop()?.toLowerCase() || 'jpg';
    const path = `${folder}/${fileName}-${Date.now()}.${ext}`;

    const { error } = await supabase.storage
      .from(BUCKET)
      .upload(path, decode(base64), {
        contentType: `image/${ext === 'jpg' ? 'jpeg' : ext}`,
        upsert: true,
      });

    if (error) {
      console.error('Upload error:', error.message);
      return null;
    }

    const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
    return data.publicUrl;
  } catch (err) {
    console.error('Upload failed:', err);
    return null;
  }
}

export async function deletePhoto(path: string): Promise<boolean> {
  const { error } = await supabase.storage.from(BUCKET).remove([path]);
  return !error;
}