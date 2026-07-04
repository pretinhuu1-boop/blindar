// FIXTURE SEGURA — next/image otimizado.
import Image from 'next/image';
export default function Page() {
  return (
    <div>
      <Image src="/a.png" alt="a" width={100} height={100} />
    </div>
  );
}
