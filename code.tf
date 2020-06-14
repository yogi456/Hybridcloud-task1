provider "aws" {

	region = "ap-south-1"
	profile = "yogi"
}
variable ssh_key_name {

        default = "keywithtf"
}
resource "tls_private_key" "key-pair" {

	algorithm = "RSA"
	rsa_bits = 4096
}

resource "local_file" "private-key" {

    content = tls_private_key.key-pair.private_key_pem
    filename = 	"${var.ssh_key_name}.pem"
    file_permission = "0400"
}

resource "aws_key_pair" "deployer" {

  key_name   = var.ssh_key_name
  public_key = tls_private_key.key-pair.public_key_openssh
}

resource "aws_security_group" "webserver" {

	name = "webserver"
	description = "Allow HTTP and SSH inbound traffic"
	
	ingress	{
		
		from_port = 80
      		to_port = 80
      		protocol = "tcp"
      		cidr_blocks = ["0.0.0.0/0"]
      		ipv6_cidr_blocks = ["::/0"]
      	}
      	
      	ingress {
      		
      		from_port = 22
      		to_port = 22
      		protocol = "tcp"
      		cidr_blocks = ["0.0.0.0/0"]
      		ipv6_cidr_blocks = ["::/0"]
      	}
      	
      	ingress {
      		
      		from_port = -1
      		to_port = -1
      		protocol = "icmp"
      		cidr_blocks = ["0.0.0.0/0"]
      		ipv6_cidr_blocks = ["::/0"]
      	}
      	
      	egress {
      	
      		from_port = 0
      		to_port = 0
      		protocol = "-1"
      		cidr_blocks = ["0.0.0.0/0"]
      	}
}
resource "aws_instance" "web" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "${var.ssh_key_name}"
  security_groups =  [ aws_security_group.webserver.name ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("${var.ssh_key_name}.pem")
    host     = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "myserver"
  }

}

resource "aws_ebs_volume" "esb1" {
	  availability_zone = aws_instance.web.availability_zone
	  size              = 1
	  tags = {
	    Name = "volweb"
	  }
	}

	resource "aws_volume_attachment" "ebs_att" {
	  device_name = "/dev/sdh"
	  volume_id   = "${aws_ebs_volume.esb1.id}"
	  instance_id = "${aws_instance.web.id}"
	  force_detach = true
	}

	output "myos_ip" {
	  value = aws_instance.web.public_ip
	}

	resource "null_resource" "nulllocal2"  {
		provisioner "local-exec" {
		    command = "echo  ${aws_instance.web.public_ip} > publicip.txt"
	  	}
	}

 resource "null_resource" "nullremote3"  {

	depends_on = [
	    aws_volume_attachment.ebs_att,
	  ]


	  connection {
	    type     = "ssh"
	    user     = "ec2-user"
	    private_key = file("${var.ssh_key_name}.pem")
	    host     = aws_instance.web.public_ip
	  }

	provisioner "remote-exec" {
	    inline = [
	      "sudo mkfs.ext4  /dev/xvdh",
	      "sudo mount  /dev/xvdh  /var/www/html",
	      "sudo rm -rf /var/www/html/*",
	      "sudo git clone https://github.com/yogi456/hybrid-cloud-task1.git /var/www/html/"
	    ]
	  }
	}
	resource "null_resource" "nulllocal1"  {


	depends_on = [
	    null_resource.nullremote3,
	  ]

		provisioner "local-exec" {
		    command = "firefox  ${aws_instance.web.public_ip}"
	  	}
	}



        resource "aws_s3_bucket" "b" {
	  bucket = "bucketfortask"
	  acl    = "private"

	  tags = {
	    Name        = "mybucket"
	    Environment = "Dev"
	  }

		provisioner "local-exec" {
		
			command = "git clone https://github.com/yogi456/imagefortask1.git image-web"
		}
		
		provisioner "local-exec" {
		
			when = destroy
			command = "rm -rf image-web"
		}
	}
	resource "aws_s3_bucket_object" "object" {
	  bucket = aws_s3_bucket.b.bucket
	  key    = "yogesh.jpeg"
	  source = "image-web/yogesh.jpeg"
	  acl    = "public-read"

	}
	locals {
	  s3_origin_id = "myS3Origin"
	}




resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.b.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

   
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "my picture"
  default_root_object = "yogesh.jpeg"

  logging_config {
    include_cookies = false
    bucket          = "yogilookbook.s3.amazonaws.com"
    prefix          = "myprefix"
  }


  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

 

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "IN"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


resource "null_resource" "nullremote4"  {

depends_on = [
    aws_cloudfront_distribution.s3_distribution
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("${var.ssh_key_name}.pem")
    host     = aws_instance.web.public_ip
  }

provisioner "remote-exec" {
    inline = [
      
  			"sudo su << EOF",
            		"echo \"<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object.key}' width='300' height='380'>\" >> /var/www/html/index.php",
            		"EOF",	
    ]
  }
  
	provisioner "local-exec" {
	    command = "firefox  ${aws_instance.web.public_ip}"
  	}
}  
  

  
  
