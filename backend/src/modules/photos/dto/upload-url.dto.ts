import { IsString, IsUUID } from 'class-validator';

/** Body cho POST /photos/upload-url (spec FR-S3-2). */
export class UploadUrlDto {
  @IsUUID()
  photoId!: string;

  @IsString()
  contentType!: string;
}
